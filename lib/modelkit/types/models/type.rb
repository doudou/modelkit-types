module ModelKit::Types
    module Models
        module Type
            include MetaRuby::ModelAsClass

            allowed_overloadings = instance_methods
            allowed_overloadings = allowed_overloadings.map(&:to_s).to_set
            allowed_overloadings.delete_if { |n| n =~ /^__/ }
            allowed_overloadings -= ["class"]
            allowed_overloadings |= allowed_overloadings.map(&:to_sym).to_set
            ALLOWED_OVERLOADINGS = allowed_overloadings.to_set

	    # The ModelKit::Types::Registry this type belongs to
            attr_reader :registry

            # Whether this is a null type, i.e. a type that cannot be actually used
            # to store values
            attr_predicate :null?, true

            # True if this is an opaque type
            #
            # Values from opaque types cannot be manipulated by ModelKit::Types. They
            # are usually used to refer to fields that will be converted first
            # (by some unspecified means) to a value that ModelKit::Types can manipulate
            attr_predicate :opaque?, true

            # Whether this type depends on an opaque type, or is an opaque type
            # itself
            attr_predicate :contains_opaques?, true

            # Whether the in-buffer size of a value of this type depends on the
            # content in the buffer (false) or not (true).
            #
            # In practice, this is false for containers and values that are
            # composed of containers
            attr_predicate :fixed_buffer_size?, true

            # @return [Integer] the size in bytes when stored in buffers
            attr_accessor :size

            # The metadata object
            #
            # @return [Metadata]
            attr_reader :metadata

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            #
            # The exact set of returned values is dependent on the exact type.
            # See the documentation of {to_h} on the subclasses of Type for more
            # details
            #
            # Some fields are always present, see {to_h_minimal}
            #
            # @option options [Boolean] :recursive (false) if true, the value
            #   returned by types that refer to other types (e.g. an array) will
            #   contain the reference's full definition. Otherwise, only the
            #   value returned by {to_h_minimal} will be stored in the
            #   type's description
            # @option options [Boolean] :layout_info (false) if true, add binary
            #   layout information from the type
            #
            # @return [Hash]
            def to_h(options = Hash.new)
                to_h_minimal(options)
            end

            # Returns the minimal description of a type using only simple ruby
            # objects (Hash, Array, Numeric and String).
            #
            #    { 'name' => TypeName,
            #      'class' => NameOfTypeClass, # CompoundType, ...
            #      'size' => SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # It is mainly used as a helper by sub-types {to_h} method when
            # :recursive is false
            #
            # @option options [Boolean] :layout_info (false) if true, add binary
            #   layout information from the type
            #
            # @return [Hash]
            def to_h_minimal(options = Hash.new)
                result = Hash[name: name, class: superclass.name.gsub(/^ModelKit::Types::/, '')]
                if options[:layout_info]
                    result[:size] = size
                end
                result
            end

            # True if this type refers to subtype of the given type, or if it a
            # subtype of +type+ itself
            def contains?(type)
                self <= type ||
                    recursive_dependencies.include?(type) || recursive_dependencies.any? { |t| t <= type }
            end

            def ==(other)
                other.kind_of?(Class) &&
                    other.superclass == self.superclass &&
                    other.name == self.name &&
                    other.size == self.size &&
                    !(other.opaque? ^ self.opaque?) &&
                    !(other.null? ^ self.null?)
            end

            # Validates that a certain type can be merged in self
            #
            # Note that this method does NOT check for global consistency. For
            # instance, it will happily merge two arrays of different types.
            # Global consistency is guaranteed by {Registry#merge}. Use this
            # method at your own risk
            #
            # @param [Model<Type>] type the compound to merge
            # @raise [InvalidMerge] if the merge is not possible
            def validate_merge(type)
                if type.name != name
                    raise MismatchingTypeNameError, "attempting to merge #{name} and #{type.name}, two types with different names"
                elsif type.supermodel != supermodel
                    raise MismatchingTypeModelError, "attempting to merge #{name} of class #{supermodel} with a type with the same name but of class #{type.supermodel}"
                elsif type.size != size
                    raise MismatchingTypeSizeError, "attempting to merge #{name} from #{registry} with the same type from #{type.registry}, but their sizes differ"
                elsif type.opaque? ^ opaque?
                    raise MismatchingTypeOpaqueFlagError, "attempting to merge #{name} from #{registry} with the same type from #{type.registry}, but their opaque flag differ"
                elsif type.null? ^ null?
                    raise MismatchingTypeNullFlagError, "attempting to merge #{name} from #{registry} with the same type from #{type.registry}, but their null flag differ"
                end
            end

            # Merge the information in type that is not in self
            def merge(type)
                metadata.merge(type.metadata)
                self
            end

            # @return [Set<Type>] returns the types that are directly referenced by self,
            #   excluding self
            #
            # @see recursive_dependencies
            attr_reader :direct_dependencies

            # Add type to the list of direct dependencies for this type, and
            # invalidate the cached value for {#recursive_dependencies}
            def add_direct_dependency(type)
                direct_dependencies << type
                @recursive_dependencies = nil
            end

            # Returns the set of all types that are needed to define self,
            # excluding self
            #
            # @return [Set<Type>]
            def recursive_dependencies
                if @recursive_dependencies
                    return @recursive_dependencies
                end

                recursive_dependencies = Set.new
                queue = direct_dependencies.to_a
                while !queue.empty?
                    t = queue.shift
                    next if recursive_dependencies.include?(t)
                    recursive_dependencies << t
                    queue.concat(t.direct_dependencies.to_a)
                end
                @recursive_dependencies = recursive_dependencies
            end

            # Sets the containing registry for an unregisterd type
            #
            # @raise [NotFromThisRegistryError] if the type is already
            #   registered in another registry
            def registry=(registry)
                if self.registry && !self.registry.equal?(registry)
                    raise NotFromThisRegistryError, "#{self} is already registered in #{self.registry}, cannot register in #{registry}"
                end
                @registry = registry
            end

            # Called by ModelKit::Types when a subclass is created.
            def setup_submodel(submodel, registry: self.registry, typename: nil, size: 0, null: false, opaque: false, &block)
                super(submodel, &block)

                submodel.instance_variable_set(:@direct_dependencies, Set.new)
                submodel.contains_opaques = opaque
                submodel.registry = registry
                submodel.name = typename
                submodel.size = size
                submodel.null = null
                submodel.opaque = opaque
                submodel.instance_variable_set(:@metadata, metadata.dup)
                submodel.fixed_buffer_size = true
            end

	    # Returns the namespace part of the type's name.  If +separator+ is
	    # given, the namespace components are separated by it, otherwise,
	    # the default of ModelKit::Types::NAMESPACE_SEPARATOR is used. If nil is
	    # used as new separator, no change is made either.
	    def namespace(separator = ModelKit::Types::NAMESPACE_SEPARATOR, remove_leading = false)
                ModelKit::Types.namespace(name, separator, remove_leading)
	    end

            # Returns the basename part of the type's name, i.e. the type name
            # without the namespace part.
            #
            # See also ModelKit::Types.basename
            def basename(separator = ModelKit::Types::NAMESPACE_SEPARATOR)
                ModelKit::Types.basename(name, separator)
            end

            # Returns the elements of this type name
            #
            # @return [Array<String>]
            def split_typename(separator = ModelKit::Types::NAMESPACE_SEPARATOR)
                ModelKit::Types.split_typename(name, separator)
            end

            # Returns the complete name for the type (both namespace and
            # basename). If +separator+ is set to a value different than
            # ModelKit::Types::NAMESPACE_SEPARATOR, ModelKit::Types's namespace separator will
            # be replaced by the one given in argument.
            #
            # For instance,
            #
            #   type_t.full_name('::')
            #
            # will return the C++ name for the given type
	    def full_name(separator = ModelKit::Types::NAMESPACE_SEPARATOR, remove_leading = false)
		namespace(separator, remove_leading) + basename(separator)
	    end

	    def to_s; "#<#{superclass.name}: #{name}>" end
            def inspect; to_s end

            # Given a markdown-formatted string, return what should be displayed
            # as text
            def pp_doc(pp, doc)
                if !doc.empty?
                    first_line = true
                    doc = doc.split("\n").map do |line|
                        if first_line
                            first_line = false
                            "/** " + line
                        else " * " + line
                        end
                    end
                    if doc.size == 1
                        doc[0] << " */"
                    else
                        doc << " */"
                    end

                    first_line = true
                    doc.each do |line|
                        if !first_line
                            pp.breakable
                        end
                        pp.text line
                        first_line = false
                    end
                    true
                end
            end

            def pretty_print(pp, with_doc: true, verbose: false) # :nodoc:
                # Metadata is nil on the "root" models, e.g. CompoundType
                if with_doc && (doc = metadata.get('doc').first)
                    if pp_doc(pp, doc)
                        pp.breakable
                    end
                end
		pp.text name 
	    end

            # Allocates a new ModelKit::Types object that is initialized from the information
            # given in the passed string
            #
            # Unlike {#from_buffer!}, the buffer is validated against the type's
            # requirements (size, ...)
            #
            # Unlike with {#wrap}, the value has its own buffer
            # 
            # @param [String] buffer
            # @return [ModelKit::Types::Type]
            def from_buffer(buffer)
                wrap(buffer.dup)
            end

            # Allocates a new ModelKit::Types object that is initialized from the information
            # given in the passed string, without validating the buffer
            #
            # Unlike with {#wrap}, the value has its own buffer
            # 
            # @param [String] buffer
            # @return [ModelKit::Types::Type]
            def from_buffer!(buffer)
                wrap!(buffer.dup)
            end

            # Give access to the value from within a buffer through a Type instance
            #
            # Unlike {#from_buffer}, it does not copy the buffer
            def wrap(buffer)
                validate_buffer(buffer)
                wrap!(buffer)
            end

            # Give access to the value from within a buffer through a Type
            # instance, without validating the provided buffer
            #
            # Unlike {#from_buffer}, it does not copy the buffer
            def wrap!(buffer)
                value = allocate
                value.initialize_subtype
                value.reset_buffer(buffer)
                value
            end

            # Validate that the given buffer could be used to back a value for
            # self
            #
            # It is expected to raise {InvalidBuffer} or one of its subclasses
            # if the buffer is invalid.
            #
            # The default implementation does nothing. This must be overloaded
            # in the Type submodels.
            def validate_buffer(buffer)
            end

            # @return [Registry] a registry that contains only the types needed
            #   to define this type
            def minimal_registry(with_aliases: true)
                registry.minimal(self, with_aliases: with_aliases)
            end

            # @return [String] a XML representation of this type
            def to_xml
                minimal_registry.to_xml
            end

            def copy_to(registry, **options)
                model = supermodel.new_submodel(
                    registry: registry, typename: name, size: size, opaque: opaque?, null: null?, **options)
                registry.register(model)
                model.metadata.merge(self.metadata)
                model
            end

            def self.extend_object(obj)
                super
                obj.instance_variable_set :@metadata, MetaData.new
                obj.instance_variable_set :@name, nil
            end

            def apply_resize(typemap)
            end

            # Returns true if this type's backing buffer can also be interpreted
            # as a value of a different type
            def casts_to?(type)
                self == type
            end
        end
    end
end

