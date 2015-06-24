module TypeStore
    module Models
        module Type
            include MetaRuby::ModelAsClass

            allowed_overloadings = instance_methods
            allowed_overloadings = allowed_overloadings.map(&:to_s).to_set
            allowed_overloadings.delete_if { |n| n =~ /^__/ }
            allowed_overloadings -= ["class"]
            allowed_overloadings |= allowed_overloadings.map(&:to_sym).to_set
            ALLOWED_OVERLOADINGS = allowed_overloadings.to_set

	    # The TypeStore::Registry this type belongs to
            attr_accessor :registry

            # Whether this is a null type, i.e. a type that cannot be actually used
            # to store values
            attr_predicate :null?, true

            # True if this is an opaque type
            #
            # Values from opaque types cannot be manipulated by TypeStore. They
            # are usually used to refer to fields that will be converted first
            # (by some unspecified means) to a value that TypeStore can manipulate
            attr_predicate :opaque?, true

            # Whether this type depends on an opaque type, or is an opaque type
            # itself
            attr_predicate :contains_opaques?, true

            # Whether this type depends on types that have convertions to ruby
            attr_predicate :contains_converted_types?, true

            # @return [Integer] the size in bytes when stored in buffers
            attr_accessor :size

            # The metadata object
            #
            # @return [Metadata]
            attr_reader :metadata

            # Definition of the unique convertion that should be used to convert
            # this type into a Ruby object
            #
            # The value is [ruby_class, options, block]. It is saved there only
            # for convenience purposes, as it is not used by TypeStore.to_ruby
            #
            # If nil, no convertions are set. ruby_class might be nil if no
            # class has been specified
            attr_accessor :convertion_to_ruby

            # Definition of the convertions between Ruby objects to this
            # TypeStore type. It is used by TypeStore.from_ruby.
            #
            # It is a mapping from a Ruby class K to a block which can convert a
            # value of class K to the corresponding TypeStore value
            attr_reader :convertions_from_ruby

            # Returns whether one needs to call TypeStore.to_ruby to convert this
            # type to the type expected by the caller
            #
            # @return [Boolean]
            def needs_convertion_to_ruby?
                !!convertion_to_ruby
            end

            # Returns whether one needs to call TypeStore.from_ruby to convert a
            # value given to the API to something this type can understand
            #
            # @return [Boolean]
            def needs_convertion_from_ruby?
                !convertions_from_ruby.empty?
            end

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
                result = Hash[name: name, class: superclass.name.gsub(/^TypeStore::/, '')]
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
            def direct_dependencies
                @direct_dependencies ||= Set.new
            end

            # Returns the set of all types that are needed to define self,
            # excluding self
            #
            # @param [Set<Type>] set if given, the new types will be added to
            #   this set. Otherwise, a new set is created. In both cases, the set is
            #   returned
            # @return [Set<Type>]
            def recursive_dependencies
                if !@recursive_dependencies
                    @recursive_dependencies = Set.new
                    direct_dependencies.each do |t|
                        if !@recursive_dependencies.include?(t)
                            @recursive_dependencies << t
                            @recursive_dependencies.merge(t.recursive_dependencies)
                        end
                    end
                end
                @recursive_dependencies
            end

            # Extends this type class so that values get automatically converted
            # to a plain Ruby type more suitable for its manipulation
            #
            # @param [Class] to the class into which self will be converted.
            #   This is here for introspection/documentation reasons
            # @yield called in the context of a Type instance and must return
            #   the converted object
            def convert_to_ruby(to = nil, &block)
                self.convertion_to_ruby = [to, Hash[block: block]]
                @converter = nil
            end

            # Extends this type class to have be able to use the Ruby class +from+
            # to initialize a value of type +self+
            def convert_from_ruby(from, &block)
                convertions_from_ruby[from] = lambda(&block)
                @converter = nil
            end

            # Returns an object that can be used to convert to/from ruby
            def ruby_domain_converter
                @ruby_domain_converter ||= RubyDomainConverter.build(self)
            end

            # Called by TypeStore when a subclass is created.
            def setup_submodel(submodel, registry: self.registry, typename: nil, size: 0, null: false, opaque: false, &block)
                super(submodel, &block)

                submodel.registry = registry
                submodel.name = typename
                submodel.size = size
                submodel.null = null
                submodel.opaque = opaque
                submodel.instance_variable_set(:@metadata, MetaData.new)
                submodel.instance_variable_set(:@convertions_from_ruby, Hash.new)

                TypeStore.type_specializations.find_all(submodel).each do |m|
                    extend m
                end
                TypeStore.value_specializations.find_all(submodel).each do |m|
                    include m
                end

                TypeStore.convertions_from_ruby.find_all(submodel).each do |conv|
                    submodel.convert_from_ruby(conv.ruby, &conv.block)
                end
                if conv = TypeStore.convertions_to_ruby.find(submodel, false)
                    submodel.convert_to_ruby(conv.ruby, &conv.block)
                end
            end

	    # The type's full name (i.e. name and namespace). In TypeStore,
	    # namespace components are separated by '/'
            #
            # @return [String]
	    def name
		if defined? @name
		    @name
		else
		    super
		end
	    end

            # Register this type on a registry
            def register(registry = self.registry)
                if self.registry && self.registry != registry
                    raise ArgumentError, "cannot change the registry of #{self} to #{registry}, already registered on #{self.registry}"
                end
                @registry = registry
                registry.register(self)
                self
            end

            def validate_layout_options(accept_opaques: false, accept_pointers: false,
                                        merge_skip_copy: true, remove_trailing_skips: true)
                return accept_opaques, accept_pointers, merge_skip_copy, remove_trailing_skips
            end

            # Returns a representation of the MemoryLayout for this type.
            #
            # The generated layout can be changed by setting one or more
            # following options:
            #
            # accept_opaques::
            #   accept types with opaques. Fields/values that are opaques are
            #   simply skipped. This is false by default: types with opaques are
            #   generating an error.
            # accept_pointers::
            #   accept types with pointers. Fields/values that are pointer are
            #   simply skipped. This is false by default: types with pointers
            #   are generating an error.
            # merge_skip_copy::
            #   in a layout, zones that contain data are copied, while zones
            #   that are there because of C++ padding rules are skipped. If this
            #   is true (the default), consecutive copy/skips are merged into
            #   one bigger copy, as doine one big memcpy() is probably more
            #   efficient than skipping the few padding bytes. Set to false to
            #   turn that off.
            # remove_trailing_skips::
            #   because of C/C++ padding rules, structures might contain
            #   trailing bytes that don't contain information. If this option is
            #   true (the default), these bytes are removed from the layout.
            def memory_layout(**options)
                do_memory_layout(*validate_layout_options(**options))
            end

	    # Returns the namespace part of the type's name.  If +separator+ is
	    # given, the namespace components are separated by it, otherwise,
	    # the default of TypeStore::NAMESPACE_SEPARATOR is used. If nil is
	    # used as new separator, no change is made either.
	    def namespace(separator = TypeStore::NAMESPACE_SEPARATOR, remove_leading = false)
                TypeStore.namespace(name, separator, remove_leading)
	    end

            # Returns the basename part of the type's name, i.e. the type name
            # without the namespace part.
            #
            # See also TypeStore.basename
            def basename(separator = TypeStore::NAMESPACE_SEPARATOR)
                TypeStore.basename(name, separator)
            end

            # Returns the elements of this type name
            #
            # @return [Array<String>]
            def split_typename(separator = TypeStore::NAMESPACE_SEPARATOR)
                TypeStore.split_typename(name, separator)
            end

            # Returns the complete name for the type (both namespace and
            # basename). If +separator+ is set to a value different than
            # TypeStore::NAMESPACE_SEPARATOR, TypeStore's namespace separator will
            # be replaced by the one given in argument.
            #
            # For instance,
            #
            #   type_t.full_name('::')
            #
            # will return the C++ name for the given type
	    def full_name(separator = TypeStore::NAMESPACE_SEPARATOR, remove_leading = false)
		namespace(separator, remove_leading) + basename(separator)
	    end

	    def to_s; "#<#{superclass.name}: #{name}>" end
            def inspect; to_s end

	    # Returns the pointer-to-self type
            def to_ptr; registry.build(name + "*") end

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

            def pretty_print(pp, with_doc = true) # :nodoc:
                # Metadata is nil on the "root" models, e.g. CompoundType
                if with_doc && metadata && (doc = metadata.get('doc').first)
                    if pp_doc(pp, doc)
                        pp.breakable
                    end
                end
		pp.text name 
	    end

            # Allocates a new TypeStore object that is initialized from the information
            # given in the passed string
            #
            # The options given here have to be exactly the same than the ones
            # given to #to_byte_array
            # 
            # @param [String] buffer
            # @option options [Boolean] accept_pointers (false) whether pointers, when
            #   present, should cause an exception to be raised or simply
            #   ignored
            # @option options [Boolean] accept_opaques (false) whether opaques, when
            #   present, should cause an exception to be raised or simply
            #   ignored
            # @option options [Boolean] merge_skip_copy (true) whether padding
            #   bytes should be marshalled as well when adjacent to non-padding
            #   bytes, to reduce CPU load at the expense of I/O. When set to
            #   false, padding bytes are removed completely.
            # @option options [Boolean] remove_trailing_skips (true) whether
            #   padding bytes at the end of the value should be marshalled or
            #   not.
            # @return [TypeStore::Type]
            def from_buffer(string, options = Hash.new)
                new.from_buffer(string, options)
            end

            # Creates a TypeStore wrapper that gives access to the memory
            # pointed-to by the given FFI pointer
            #
            # The returned TypeStore object will not care about deallocating the
            # memory
            #
            # @param [FFI::Pointer] ffi_ptr the memory address at which the
            #   value is
            # @return [Type] the TypeStore object that gives access to the data
            #   pointed-to by ffi_ptr
            def from_ffi(ffi_ptr)
                raise NotImplementedError
                from_address(ffi_ptr.address)
            end

	    # Check if this type is a +typename+. If +typename+
	    # is a string or a regexp, we match it against the type
	    # name. Otherwise we call Class#<
	    def is_a?(typename)
		if typename.respond_to?(:to_str)
		    typename.to_str === self.name
		elsif Regexp === typename
		    typename === self.name
		else
		    self <= typename
		end
	    end

            # @return [Registry] a registry that contains only the types needed
            #   to define this type
            def minimal_registry
                registry.minimal(name, true)
            end

            # @return [String] a XML representation of this type
            def to_xml
                minimal_registry.to_xml
            end

            def initialize_base_class
            end

            def ruby_convertion_candidates_on(ruby_mappings)
                candidates = (ruby_mappings.from_typename[name] || Array.new)
                ruby_mappings.from_regexp.each do |matcher, registered|
                    if matcher === name
                        candidates.concat(registered)
                    end
                end
                candidates
            end
        end
    end
end

