module TypeStore
    # In TypeStore, a registry contains a consistent set of types, i.e. the types
    # are that are related to each other.
    #
    # As mentionned in the TypeStore module documentation, it is better to
    # manipulate value objects from types from the same registry. That is more
    # efficient, as it removes the need to compare the type definitions whenever
    # the values are manipulated together.
    #
    # I.e., it is better to use a global registry to represent all the types
    # used in your application. In case you need to load different registries,
    # that can be achieved by +merging+ them together (which will work only if
    # the type definitions match between the registries).
    class Registry
        TYPE_BY_EXT = {
            ".c" => "c",
            ".cc" => "c",
            ".cxx" => "c",
            ".cpp" => "c",
            ".h" => "c",
            ".hh" => "c",
            ".hxx" => "c",
            ".hpp" => "c",
            ".tlb" => "tlb"
        }

        IMPORT_TYPE_HANDLERS = Hash.new
        EXPORT_TYPE_HANDLERS = Hash.new

        # The typename-to-type mapping
        #
        # @return [Hash<String,Type>]
        attr_reader :types

        # The typename-to-container mapping
        #
        # @return [Hash<String,ContainerType>]
        attr_reader :container_models

        # The object that manages class extensions as well as conversions
        # to/from Ruby
        #
        # @return [SpecializationManager]
        attr_reader :specialization_manager

        def initialize(specialization_manager: TypeStore.specialization_manager.dup)
            @types = Hash.new
            @container_models = Hash.new
            @specialization_manager = specialization_manager ||
                SpecializationManager.new
        end

        def size
            types.size
        end

        def dup
            copy = Registry.new
            copy.merge(self)
            copy
        end

        # Creates a new registry by loading a TypeStore XML file
        #
        # @see Registry#merge_xml
        def self.from_xml(xml)
            if xml.respond_to?(:to_str)
                xml = REXML::Document.new(xml)
            end
            TypeStore::IO::XMLImporter.new.from_xml(xml, registry: new)
        end

        # Enumerate the types contained in this registry
        #
        # @overload each(prefix, :with_aliases => false)
        #   Enumerates the types and not the aliases
        #
        #   @param [nil,String] prefix if non-nil, only types whose name is this prefix
        #     will be enumerated
        #   @yieldparam [Model<TypeStore::Type>] type a type
        #
        # @overload each(prefix, :with_aliases => true)
        #   Enumerates the types and the aliases
        #
        #   @param [nil,String] prefix if non-nil, only types whose name is this prefix
        #     will be enumerated
        #   @yieldparam [String] name the type name, it is different from type.name for
        #     aliases
        #   @yieldparam [Model<TypeStore::Type>] type a type
        def each(filter = nil, with_aliases: false)
            return enum_for(__method__, filter, with_aliases: with_aliases) if !block_given?

            if filter.respond_to?(:to_str)
                filter = Regexp.new("^#{Regexp.quote(filter)}")
            end

            if with_aliases
                types.each do |name, type|
                    next if filter && !(filter === name)
                    yield(name, type)
                end
            else
                types.each_value do |type|
                    next if filter && !(filter === type.name)
                    yield(type)
                end
            end
        end
        include Enumerable

        # Add all types from a registry to self
        #
        # @param [Registry] registry
        # @raise [InvalidMergeError] if some types in the registry have the same
        #   name than types in self, but with different definitions
        def merge(registry)
            # First, verify that all common types are compatible
            common_types = Array.new
            missing_types = Array.new
            new_aliases = Hash.new { |h, k| h[k] = Set.new }
            registry.types.each do |name, type|
                if self_type = find_by_name(name)
                    begin
                        self_type.validate_merge(type)
                    rescue InvalidMergeError => e
                        if name == type.name
                            raise
                        else
                            raise e, "merged registry aliases #{type} under the name #{name} but #{name} resolves to #{self_type} on the receiver: #{e.message}"
                        end
                    end

                    if name == type.name
                        common_types << [type, self_type]
                    end
                elsif type.name == name
                    missing_types << type
                else
                    new_aliases[type.name] << name
                end
            end

            common_types.each do |type, self_type|
                self_type.merge(type)
            end
            missing_types.each do |type|
                if !find_by_name(type.name) # Has been copied because of a dependency
                    type.copy_to(self)
                end
            end
            new_aliases.each do |name, aliases|
                aliases.each do |n|
                    create_alias(n, name)
                end
            end
            self
        end

        # Generates the smallest new registry that allows to define a set of types
        #
        # @param [String] type_name the name of a type
        # @param [Boolean] with_aliases if true, aliases defined in self that
        #   point to types ending up in the minimal registry will be copied
        # @return [Registry] the registry that allows to define the
        #   named type
	def minimal(type, with_aliases: true)
            type = validate_type_argument(type)

            result = Registry.new
            type.copy_to(result)
            if with_aliases
                new_type = result.get(type.name)
                aliases_of(type).each do |name|
                    result.create_alias(name, new_type)
                end
            end
            result
	end

        # Generates the smallest new registry that defines all types of self
        # except some
        #
        # Note that types in the removed_types registry might be present in the
        # result if some other types need them
        #
        # @param [Registry] removed_types a registry containing the
        #   types that are not necessary in the result
        # @param [Boolean] with_aliases if true, aliases defined in self that
        #   point to types ending up in the minimal registry will be copied
        # @return [Registry] the registry that allows to define all
        #   types of self that are not in auto_types. Note that it may contain
        #   types that are in the auto_types registry, if they are needed to
        #   define some other type
        def minimal_without(removed_types, with_aliases: true)
            removed_types =
                removed_types.map { |t| validate_type_argument(t) }.
                to_set

            result = Registry.new
            registry.types.each do |name, type|
                next if removed_types.include?(type)
                type.copy_to(result)
            end

            if with_aliases
                each_alias do |name, type|
                    if result.include?(type.name)
                        result.create_alias(name, type.name)
                    end
                end
            end
            result
        end

        # Returns a type by its name, or nil if none under that name exists
        #
        # @param [String] name the type name
        # @return [Model<Type>]
        def find_by_name(name)
            types[name]
        end

        # Tests for the presence of a type by its name
        #
        # @param [String] name the type name
        # @return [Boolean] true if this registry contains a type named like
        #   this
        def include?(name)
            !!find_by_name(name)
        end

        # Export this registry in the Ruby namespace. The base namespace under
        # which it should be done is given in +base_module+
        def export_to_ruby(base_module, options = Hash.new, &block)
            base_module.extend RegistryExport
            base_module.reset_registry_export(self, block)
        end

	# Returns the file type as expected by TypeStore from 
	# the extension of +file+ (see TYPE_BY_EXT)
	#
	# Raises RuntimeError if the file extension is unknown
        def self.guess_type(file)
	    ext = File.extname(file)
            if type = TYPE_BY_EXT[ext]
		type
            else
                raise UnknownFileTypeError, "Cannot guess file type for #{file}: unknown extension '#{ext}'"
            end
        end

	# Format +option_hash+ to the form expected by do_import
	# (Yes, I'm lazy and don't want to handles hashes in C)
        def self.format_options(option_hash) # :nodoc:
            option_hash.to_a.collect do |opt|
                if opt[1].kind_of?(Array)
                    if opt[1].first.kind_of?(Hash)
                        [ opt[0].to_s, opt[1].map { |child| format_options(child) } ]
                    else
                        [ opt[0].to_s, opt[1].map { |child| child.to_s } ]
                    end
                elsif opt[1].kind_of?(Hash)
                    [ opt[0].to_s, format_options(opt[1]) ]
                else
                    [ opt[0].to_s, opt[1].to_s ]
                end
            end
        end

        # Shortcut for
        #   registry = Registry.new
        #   registry.import(args)
        #
        # See Registry#import
        def self.import(*args)
            registry = Registry.new
            registry.import(*args)
            registry
        end

        # Returns the handler that will be used to import that file. It can
        # either be a string, in which case we use a TypeStore internal importer,
        # or a Ruby object responding to 'call' in which case Registry#import
        # will use that object to do the importing.
        def self.import_handler_for(file, kind = 'auto')
	    file = File.expand_path(file)
            if !kind || kind == 'auto'
                kind    = Registry.guess_type(file)
            end
            if handler = IMPORT_TYPE_HANDLERS[kind]
                return handler
            end
            return kind
        end

        # Imports the +file+ into this registry. +kind+ is the file format or
        # nil, in which case the file format is guessed by extension (see
        # TYPE_BY_EXT)
	# 
        # +options+ is an option hash. The Ruby bindings define the following
        # specific options:
	# merge:: 
        #   merges +file+ into this repository. If this is false, an exception
        #   is raised if +file+ contains types already defined in +self+, even
        #   if the definitions are the same.
	#
	#     registry.import(my_path, 'auto', :merge => true)
	#
	# The Tlb importer has no options
	#
        # The C importer defines the following options: preprocessor:
        #
	# define:: 
        #   a list of VAR=VALUE or VAR options for cpp
	#     registry.import(my_path, :define => ['PATH=/usr', 'NDEBUG'])
	# include:: 
        #   a list of path to add to cpp's search path
	#     registry.import(my_path, :include => ['/usr', '/home/blabla/prefix/include'])
	# rawflags:: 
        #   flags to be passed as-is to cpp. For instance, the two previous
        #   examples can be written
	#
	#   registry.import(my_path, 'auto',
	#     :rawflags => ['-I/usr', '-I/home/blabla/prefix/include', 
	#                  -DPATH=/usr', -DNDEBUG])
	# debug::
        #   if true, debugging information is outputted on stdout, and the
        #   preprocessed output is kept.
        #
        # merge::
        #   load the file into its own registry, and merge the result back into
        #   this one. If it is not set, types defined in +file+ that are already
        #   defined in +self+ will generate an error, even if the two
        #   definitions are the same.
	#
        def import(file, kind = 'auto', **options)
	    file = File.expand_path(file)
            if handler = Registry.import_handler_for(file, kind)
                return handler.import(file, registry: self, **options)
            else
                raise ArgumentError, "no importer defined for #{file} (#{kind})"
            end
        end

        def each_type_topological
            return enum_for(__method__) if !block_given?

            remaining = types.values
            queue = Array.new
            sorted = Set.new
            while !remaining.empty?
                type = remaining.shift
                next if sorted.include?(type)
                queue.push type

                while !queue.empty?
                    type = queue.pop
                    next if sorted.include?(type)
                    deps = type.direct_dependencies.find_all { |t| !sorted.include?(t) }
                    if deps.empty?
                        sorted << type
                        yield(type)
                    else
                        queue.push type
                        queue.concat(deps)
                    end
                end
            end
        end

        # Resizes the given type to the given size, while updating the rest of
        # the registry to keep it consistent
        #
        # In practice, it means it modifies the compound field offsets and
        # sizes, and modifies the array sizes so that it matches the new sizes.
        #
        # +type+ must either be a type class or a type name, and to_size the new
        # size for it.
        #
        # See #resize to resize multiple types in one call.
        def resize_type(type, to_size)
            resize(type => to_size)
        end

        # Resize a set of types, while updating the rest of the registry to keep
        # it consistent
        #
        # In practice, it means it modifies the compound field offsets and
        # sizes, and modifies the array sizes so that it matches the new sizes.
        #
        # The given type map must be a mapping from a type name or type class to
        # the new size for that type.
        #
        # See #resize to resize multiple types in one call.
        def resize(typemap)
            typemap = typemap.map_key do |type, size|
                validate_type_argument(type)
            end
            each_type_topological do |t|
                min_size = t.apply_resize(typemap)
                explicit_size = typemap[t]
                if min_size && explicit_size && explicit_size < min_size
                    raise InvalidSizeSpecifiedError, "#{explicit} specified as new size for #{t}, but this type has to be at least of size #{min_size}"
                end
                if explicit_size
                    t.size = explicit_size
                elsif min_size
                    t.size = min_size
                end
                typemap[t] = t.size
            end
        end

        # @deprecated use the exporter objects in {TypeStore::IO} directly
	def export(kind, **options)
            if handler = EXPORT_TYPE_HANDLERS[kind]
                return handler.export(self, **options)
            else
                raise ArgumentError, "no exporter defined for #{kind}"
            end
	end

        # Export the registry into TypeStore's own XML format
        #
        # @return [REXML::Document]
        def to_xml
            IO::XMLExporter.new.to_xml(self)
        end

        # Helper class for Registry#create_compound
        class CompoundBuilder
            # The compound type being built
            attr_reader :type
            # The offset for the next field
            attr_reader :current_size

            def initialize(name, registry, **options)
                @current_size = 0
                @type = CompoundType.new_submodel(typename: name, registry: registry, **options)
            end
            
            # Create the type on the underlying registry
            def build
                type.size ||= current_size
                type.register
            end

            def skip(count)
                @current_size += count
            end

            # Adds a new field
            #
            # @param [String] name the field name
            # @param [Type,String] type the field's type
            # @param [Integer,nil] offset the field offset. If nil, it is
            #   automatically computed in #build so as to follow the previous
            #   field.
            # @return [Field]
            def add(field_name, field_type, _offset = nil, offset: current_size)
                offset ||= _offset
                field = type.add(field_name.to_s, field_type, offset: offset)
                @current_size = [current_size, field.offset + field.type.size].max
                field
            end

            def method_missing(name, *args, &block)
                if name.to_s =~ /^(.*)=$/
                    type = args.first
                    name = $1
                    add($1, type)
                else
                    super
                end
            end
        end

        # Registers the given class as a container type
        def register_container_model(type)
            TypeStore.validate_typename(type.name)
            if container_models.has_key?(type.name)
                raise DuplicateTypeNameError, "attempting to redefine the existing container model #{type.name}"
            end
            container_models[type.name] = type
        end

        # Enumerate the available container kinds
        #
        # @yieldparam [Model<Type>] the container base class
        def each_available_container_model(&block)
            container_models.values.each(&block)
        end

        def has_container_model?(name)
            container_models.has_key?(name)
        end

        def find_container_model_by_name(name)
            container_models[name.to_str]
        end

        # Returns the container base model with the given name
        def container_model(name)
            if type = container_models[name.to_s]
                type
            else
                raise NotFound, "#{self} has no container type named #{name}"
            end
        end

        def register(type, name: type.name)
            TypeStore.validate_typename(name)
            if types.has_key?(name)
                raise DuplicateTypeNameError, "attempting to register #{type} as #{name} but there is already #{types[name]} under that name"
            elsif type.registry && !type.registry.equal?(self)
                raise NotFromThisRegistryError, "#{type} is not a type model from #{self} but from #{type.registry}, cannot register"
            end

            type.registry = self
            types[name] = type
        end

        def create_opaque(name, _size = 0, size: nil)
            size ||= _size
            register(Type.new_submodel(typename: name, registry: self, opaque: true, size: size))
        end

        def create_null(name)
            register(Type.new_submodel(typename: name, registry: self, null: true))
        end

        # Create a type of unspecified model (usually for nul/opaque types)
        def create_type(name, **options)
            register(Type.new_submodel(typename: name, registry: self, **options))
        end

        def create_numeric(name, **options)
            register(NumericType.new_submodel(typename: name, registry: self, **options))
        end

        # Creates a new compound type with the given name on this registry
        #
        # @yield [CompoundBuilder] the compound building helper, see below for
        #   examples. Only the #add method allows to set offsets. When no
        #   offsets are given, they are computed from the previous field.
        # @return [Type] the type representation
        #
        # @example create a compound using #add
        #   registry.create_compound "/new/Compound" do |c|
        #     c.add "field0", "/int", 15
        #     c.add "field1", "/another/Compound", 20
        #   end
        #
        # @example create a compound using the c.field = type syntax
        #   registry.create_compound "/new/Compound" do |c|
        #     c.field0 = "/int"
        #     c.field1 = "/another/Compound"
        #   end
        #
        def create_compound(name, _size = nil, size: nil, **options)
            size ||= _size
            recorder = CompoundBuilder.new(name, self, size: size, **options)
            yield(recorder) if block_given?
            recorder.build
        end

        # Creates a new container type on this registry
        #
        # @param [String] container_model the name of the container type
        # @param [String,Type] element_type the type of the container elements,
        #   either as a type or as a type name
        #
        # @example create a new std::vector type
        #   registry.create_container "/std/vector", "/my/Container"
        def create_container(container_model, element_type, _size = nil, typename: nil, size: nil, **options)
            if container_model.respond_to?(:to_str)
                container_model_name = container_model
                if !(container_model = container_models[container_model])
                    raise NotFound, "#{container_model_name} is not a valid container type name on #{self}"
                end
            end
            element_type = validate_type_argument(element_type)

            size ||= _size
            typename ||= "#{container_model.name}<#{element_type.name}>"
            size = nil if size == 0
            size ||= container_model.size

            container_t = container_model.
                new_submodel(registry: self, typename: typename,
                             deference: element_type, size: size, **options)
            container_t.register
        end

        # Creates a new array type on this registry
        #
        # @param [String,Type] base_type the type of the array elements,
        #   either as a type or as a type name
        # @param [Integer] length the number of elements in the array
        #
        # @example create a new array of 10 elements
        #   registry.create_array "/my/Container", 10
        def create_array(element_type, length = 0, _size = nil, size: nil, typename: nil, **options)
            # For backward compatibility with typelib
            size ||= _size
            size = nil if size == 0

            element_type = validate_type_argument(element_type)
            typename ||= "#{element_type.name}[#{length}]"
            size     ||= element_type.size * length
            TypeStore.validate_typename(typename)
            array_t = ArrayType.new_submodel(deference: element_type, typename: typename, registry: self,
                                   length: length, size: size, **options)
            array_t.register
        end

        # Helper class to build new enumeration types
        class EnumBuilder
            # The type being built
            attr_reader :type
            # The value for the next symbol
            attr_reader :current_value

            def initialize(name, registry, **options)
                @current_value = 0
                @type = EnumType.new_submodel(typename: name, registry: registry, **options)
            end
            
            # Creates the new enum type on the registry
            def build
                type.register
            end

            # Add a new symbol to this enum
            def add(name, value = current_value)
                type.add(name.to_s, Integer(value))
                @current_value = Integer(value) + 1
            end

            # Alternative method to add new symbols. See {Registry#create_enum}
            # for examples.
            def method_missing(name, *args, &block)
                if name.to_s =~ /^(.*)=$/
                    value = args.first
                    add($1, value)
                elsif args.empty?
                    add(name.to_s)
                else
                    super
                end
            end
        end

        # Creates a new enum type with the given name on this registry
        #
        # @yield [EnumBuilder] the enum building helper. In both methods, if a
        #   symbol's value is not provided, it is computed as last_value + 1
        # @return [Type] the type representation
        #
        # @example create an enum using #add
        #   registry.create_enum "/new/Enum" do |c|
        #     c.add "sym0", 15
        #     c.add "sym1", 2
        #     # sym2 will be 3
        #     c.add "sym2"
        #   end
        #
        # @example create an enum using the c.sym = value syntax
        #   registry.create_enum "/new/Enum" do |c|
        #     c.sym0 = 15
        #     c.sym1 = 2
        #     # sym2 will be 3
        #     c.sym2
        #   end
        #
        def create_enum(name, _size = nil, size: nil, **options)
            size ||= _size
            recorder = EnumBuilder.new(name, self, size: size, **options)
            yield(recorder)
            recorder.build
        end

        def validate_container_model_argument(type)
            if type.respond_to?(:to_str)
                if !(container_t = container_models[type.to_str])
                    raise NotFound, "no container type #{type} in #{self}"
                end
                container_t
            elsif type.registry != self
                raise NotFromThisRegistryError, "#{type} is not from #{self}"
            else
                type
            end
        end

        def validate_type_argument(type)
            if type.respond_to?(:to_str)
                get(type)
            elsif type.registry != self
                raise NotFromThisRegistryError, "#{type} is not from #{self}"
            else
                type
            end
        end

        # Registers an existing type under a different name
        #
        # @param [String] new_name the new name
        # @param [String,Model<Type>] old_type the type to be aliased
        # @raise (see validate_type_argument)
        # @raise (see register)
        def create_alias(new_name, old_type)
            register(validate_type_argument(old_type), name: new_name)
        end

        def each_alias
            return enum_for(__method__) if !block_given?
            each(with_aliases: true) do |name, type|
                yield(name, type) if name != type.name
            end
        end

        def aliases_of(type)
            all_names = types.keys.find_all do |name|
                types[name] == type
            end
            all_names.delete(type.name)
            all_names
        end

        def clear_aliases
            types.delete_if do |name, type|
                name != type.name
            end
        end

        def get(typename)
            if type = types[typename]
                type
            else
                raise NotFound, "no type #{typename} in #{self}"
            end
        end

        # Build a derived type (array or container) from its canonical name
        def build(typename, size = nil)
            get(typename)
        rescue NotFound => e
            if typename =~ /^(.*)\[(\d+)\]$/
                element_name = $1
                length = Integer($2)
                element_t = build(element_name)
                if element_t.name != element_name
                    # The element type is an alias. The container type  might
                    # already exist under its canonical name, call #build to
                    # make sure, and create an alias
                    array_t = build("#{element_t.name}[#{length}]")
                    create_alias(typename, array_t)
                else
                    array_t = create_array(element_t, length, size: size)
                end
                return array_t
            end

            namespace, basename = TypeStore.split_typename(typename)
            container_t_name, arguments = TypeStore.parse_template(basename)
            if !arguments.empty?
                # Always register auto-created containers like this under their
                # canonical name, and then alias if necessary
                element_t = build(arguments[0])
                if element_t.name != arguments[0]
                    # The element type is an alias. The container type  might
                    # already exist under its canonical name, call #build to
                    # make sure, and create an alias
                    container_t = build("#{namespace}#{container_t_name}<#{element_t.name}>")
                    create_alias(typename, container_t)
                else
                    container_t = create_container("#{namespace}#{container_t_name}", element_t, size: size)
                end
                container_t
            else
                raise e, "#{e.message}, and it cannot be built", e.backtrace
            end
        end

        # Add a type from a different registry to this one
        #
        # @param [Class<TypeStore::Type>] the type to be added
        # @return [void]
        def add(type)
            merge(type.registry.minimal(type.name))
            nil
        end
    end
end
