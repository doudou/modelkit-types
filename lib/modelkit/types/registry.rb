module ModelKit::Types
    # In ModelKit::Types, a registry contains a consistent set of types, i.e. the types
    # are that are related to each other.
    #
    # As mentionned in the ModelKit::Types module documentation, it is better to
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

        def initialize
            @types = Hash.new
            @container_models = Hash.new
        end

        def size
            types.size
        end

        # Compare whether two registries contain the same types
        def same_types?(other)
            types == other.types
        end

        def dup
            copy = Registry.new
            copy.merge(self)
            copy
        end

        # Creates a new registry by loading a ModelKit::Types XML file
        #
        # @param [String,REXML::Document] xml a registry marshalled into XML
        # @return [Registry]
        def self.from_xml(xml)
            if xml.respond_to?(:to_str)
                xml = REXML::Document.new(xml)
            end
            ModelKit::Types::IO::XMLImporter.new.from_xml(xml, registry: new)
        end

        # Enumerate the types contained in this registry
        #
        # @overload each(prefix, :with_aliases => false)
        #   Enumerates the types and not the aliases
        #
        #   @param [nil,String] prefix if non-nil, only types whose name is this prefix
        #     will be enumerated
        #   @yieldparam [Model<ModelKit::Types::Type>] type a type
        #
        # @overload each(prefix, :with_aliases => true)
        #   Enumerates the types and the aliases
        #
        #   @param [nil,String] prefix if non-nil, only types whose name is this prefix
        #     will be enumerated
        #   @yieldparam [String] name the type name, it is different from type.name for
        #     aliases
        #   @yieldparam [Model<ModelKit::Types::Type>] type a type
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
                types.each do |name, type|
                    next if name != type.name
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
            each do |type|
                next if removed_types.include?(type) || result.include?(type.name)
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
        def export_to_ruby(base_module, &block)
            base_module.extend RegistryExport
            base_module.reset_registry_export(self, block)
        end

        # Returns the file type as expected by ModelKit::Types from 
        # the extension of +file+ (see TYPE_BY_EXT)
        #
        # Raises RuntimeError if the file extension is unknown
        def self.guess_type(file)
            ext = File.extname(file)
            if type = TYPE_BY_EXT[ext]
                type
            else
                raise UnknownFileTypeError, "cannot guess file type for #{file}: unknown extension '#{ext}'"
            end
        end

        # Create a registry and import into it
        def self.import(file, kind: 'auto', **options)
            registry = Registry.new
            registry.import(file, kind: 'auto', **options)
            registry
        end

        # Returns the handler that will be used to import that file.
        #
        # The return value is an object which responds to #import
        def self.import_handler_for(file, kind)
            file = File.expand_path(file)
            if handler = IMPORT_TYPE_HANDLERS[kind]
                return handler
            end
        end

        # Imports the types defined in a file into this registry
        #
        # @param [String] file the path to the file
        # @param [String] kind the file type, or 'auto' to guess the type from
        #   the file's extension
        def import(file, kind: 'auto', **options)
            file = File.expand_path(file)
            if kind == 'auto'
                kind = Registry.guess_type(file)
            end
            if handler = Registry.import_handler_for(file, kind)
                return handler.import(file, registry: self, **options)
            else
                raise ArgumentError, "no importer defined for #{file}, detected as #{kind}"
            end
        end

        # @deprecated use the exporter objects in {ModelKit::Types::IO} directly
        def export(kind, **options)
            if handler = EXPORT_TYPE_HANDLERS[kind]
                return handler.export(self, **options)
            else
                raise ArgumentError, "no exporter defined for #{kind}"
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
                    raise InvalidSizeSpecifiedError, "#{explicit_size} specified as new size for #{t}, but this type has to be at least of size #{min_size}"
                end
                if explicit_size
                    t.size = explicit_size
                elsif min_size
                    t.size = min_size
                end
                typemap[t] = t.size
            end
        end

        # Export the registry into ModelKit::Types's own XML format
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
            # The registry on which we build this type
            attr_reader :registry

            def initialize(name, registry, **options)
                @current_size = 0
                @registry = registry
                @type = CompoundType.new_submodel(typename: name, registry: registry, **options)
            end

            # Create the type on the underlying registry
            def build
                type.size ||= current_size
                registry.register(type)
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
            def add(field_name, field_type, offset: current_size, skip: 0)
                field = type.add(field_name.to_s, field_type, offset: offset, skip: skip)
                @current_size = [current_size, field.offset + field.size].max
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

        # Create a new container model
        def create_container_model(name)
            ModelKit::Types.validate_typename(name)
            container_model = ContainerType.new_submodel
            container_model.name = name
            register_container_model(container_model)
            container_model
        end

        # Registers the given class as a container type
        def register_container_model(type)
            ModelKit::Types.validate_typename(type.name)
            if container_models.has_key?(type.name)
                raise DuplicateTypeNameError, "attempting to redefine the existing container model #{type.name}"
            end
            container_models[type.name] = type
        end

        # Enumerate the available container kinds
        #
        # @yieldparam [Models::ContainerType] the container base class
        def each_available_container_model(&block)
            container_models.each_value(&block)
        end

        # Tests whether a container model exists under this name
        #
        # @param [String] name the container model name
        def has_container_model?(name)
            container_models.has_key?(name.to_str)
        end

        # Returns the container base model with the given name, or nil
        #
        # @param [String] name the container model name
        # @return [nil,Models::ContainerType] the container model or nil if no
        #   container models exist under that name
        # @see container_model_by_name
        def find_container_model_by_name(name)
            container_models[name.to_str]
        end

        # Returns the container base model with the given name
        #
        # @param [String] name the container model name
        # @raise [NotFound] if there are no container models with the requested
        #   name
        # @see find_container_model_by_name
        def container_model_by_name(name)
            if model = find_container_model_by_name(name)
                model
            else
                raise NotFound, "#{self} has no container type named #{name}"
            end
        end

        # Register a type in this registry
        #
        # @param [Models::Type] the type model
        # @param [String] name the name under which the type should be
        #   registered
        #
        # @raise DuplicateTypeNameError if a type is already registered under
        #   the name
        # @raise NotFromThisRegistryError if the type model is already
        #   registered in another registry
        def register(type, name: type.name)
            ModelKit::Types.validate_typename(name)
            if types.has_key?(name)
                raise DuplicateTypeNameError, "attempting to register #{type} as #{name} but there is already #{types[name]} under that name"
            elsif type.registry && !type.registry.equal?(self)
                raise NotFromThisRegistryError, "#{type} is not a type model from #{self} but from #{type.registry}, cannot register"
            end

            type.registry = self
            types[name] = type
        end

        # Add a type from a different registry to this one
        #
        # @param [Models::Type] the type to be added
        # @return [void]
        def add(type)
            if !type.registry.equal?(self)
                merge(type.registry.minimal(type.name))
            end
            nil
        end

        # Create a new opaque object
        #
        # @return [Models::Type]
        def create_opaque(name, size: nil, **options)
            create_type(name, size: size, opaque: true, **options)
        end

        # Create a new opaque object on this registry
        #
        # @return [Models::Type]
        def create_null(name, size: nil, **options)
            create_type(name, size: size, null: true, **options)
        end

        # Create a plain type object on this registry
        #
        # @return [Models::Type]
        def create_type(name, **options)
            register(Type.new_submodel(typename: name, registry: self, **options))
        end

        # Create a character type object on this registry
        #
        # @return [Models::CharacterType]
        def create_character(name, **options)
            register(CharacterType.new_submodel(typename: name, registry: self, **options))
        end

        # Create a numeric type object on this registry
        #
        # @return [Models::NumericType]
        def create_numeric(name, **options)
            register(NumericType.new_submodel(typename: name, registry: self, **options))
        end

        # Creates a compound type object on this registry
        #
        # @yield [CompoundBuilder] the compound building helper, see below for
        #   examples. Only the #add method allows to set offsets. When no
        #   offsets are given, they are computed from the previous field.
        # @return [Models::CompoundType]
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
        # @param [String] container_model the name of the container model
        # @param [String,Type] element_type the type of the container elements,
        #   either as a type or as a type name
        # @param [String,nil] typename the created type name. If nil, a default
        #   name will be generated from the container model name and the element
        #   type name
        # @return [Models::ContainerType]
        #
        # @example create a new std::vector type
        #   registry.create_container "/std/vector", "/my/Container"
        def create_container(container_model, element_type, _size = nil, typename: nil, size: nil, **options)
            if container_model.respond_to?(:to_str)
                container_model = container_model_by_name(container_model)
            end
            element_type = validate_type_argument(element_type)

            size ||= _size
            typename ||= "#{container_model.name}<#{element_type.name}>"
            size = nil if size == 0
            size ||= container_model.size

            container_t = container_model.
                new_submodel(registry: self, typename: typename,
                             deference: element_type, size: size, **options)
            register(container_t)
            container_t
        end

        # Creates a new array type on this registry
        #
        # @param [String,Type] base_type the type of the array elements,
        #   either as a type or as a type name
        # @param [Integer] length the number of elements in the array
        # @param [String,nil] typename the created type name. If nil, a default
        #   name will be generated from the element type name
        # @return [Models::ArrayType]
        #
        # @example create a new array of 10 elements
        #   registry.create_array "/my/Container", 10
        def create_array(element_type, length = 0, size: nil, typename: nil, **options)
            element_type = validate_type_argument(element_type)
            typename ||= "#{element_type.name}[#{length}]"
            if !size && element_type.size
                size     = element_type.size * length
            end
            ModelKit::Types.validate_typename(typename)
            array_t = ArrayType.new_submodel(deference: element_type, typename: typename, registry: self,
                                             length: length, size: size, **options)
            register(array_t)
        end

        # @api private
        #
        # Helper class to build new enumeration types
        class EnumBuilder
            # The type being built
            attr_reader :type
            # The value for the next symbol
            attr_reader :current_value
            # The registry for which we build this enum
            attr_reader :registry

            def initialize(name, registry, **options)
                @current_value = 0
                @registry = registry
                @type = EnumType.new_submodel(typename: name, registry: registry, **options)
            end

            # Creates the new enum type on the registry
            def build
                registry.register(type)
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

        # Creates a new enum type on this registry
        #
        # @yield [EnumBuilder] the enum building helper. In both methods, if a
        #   symbol's value is not provided, it is computed as last_value + 1
        # @return [Models::EnumType] the type representation
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

        # @api private
        #
        # Helper method that validates a type argument
        #
        # It either resolves it from a string, or verifies that the type is
        # indeed within the registry
        #
        # @raise NotFromThisRegistryError if the type is not a type object from
        #   this registry
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

        # Enumerate all aliases defined on this registry
        #
        # @yieldparam [String,Nodels::Type]
        # @return [void]
        def each_alias
            return enum_for(__method__) if !block_given?
            each(with_aliases: true) do |name, type|
                yield(name, type) if name != type.name
            end
        end

        # Returns the aliases existing for a given type
        #
        # @return [Array<String>] the list of aliases, not including the type's
        #   actual name
        def aliases_of(type)
            all_names = types.keys.find_all do |name|
                types[name] == type
            end
            all_names.delete(type.name)
            all_names
        end

        # Remove all aliases from the registry
        def clear_aliases
            types.delete_if do |name, type|
                name != type.name
            end
        end

        # Returns a type from its name
        #
        # @param [String] typename the type name
        # @return [Models::Type] the type model
        # @raise [NotFound] if there are no types registered under that name
        def get(typename)
            if type = types[typename.to_str]
                type
            else
                raise NotFound, "no type #{typename} in #{self}"
            end
        end

        # Build a derived type (array or container) from its canonical name
        #
        # Arrays are written `/typename[10]`, containers
        # `/container_model</container_element_type>`
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

            namespace, basename = ModelKit::Types.split_typename(typename)
            container_t_name, arguments = ModelKit::Types.parse_template(basename)
            container_t_name = "#{namespace}#{container_t_name}"
            if !arguments.empty?
                if !has_container_model?(container_t_name)
                    raise NotFound, "cannot build #{typename}: #{container_t_name} is not a known container type"
                end

                # Always register auto-created containers like this under their
                # canonical name, and then alias if necessary
                element_t = build(arguments[0])
                if element_t.name != arguments[0]
                    # The element type is an alias. The container type  might
                    # already exist under its canonical name, call #build to
                    # make sure, and create an alias
                    container_t = build("#{container_t_name}<#{element_t.name}>")
                    create_alias(typename, container_t)
                else
                    container_t = create_container("#{container_t_name}", element_t, size: size)
                end
                container_t
            else
                raise e, "#{e.message}, and it cannot be built", e.backtrace
            end
        end
    end
end

