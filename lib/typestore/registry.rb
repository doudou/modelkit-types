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

        TYPE_HANDLERS = Hash.new

        # The typename-to-type mapping
        #
        # @return [Hash<String,Type>]
        attr_reader :types

        def initialize(load_plugins: TypeStore.load_plugins?)
            @types = Hash.new
	    if load_plugins
            	TypeStore.load_plugins
            end
        end

        def dup
            copy = self.class.new
            copy.merge(self)
            copy
        end

        # Generates the smallest new registry that allows to define a set of types
        #
        # @overload minimal(type_name, with_aliases = true)
        #   @param [String] type_name the name of a type
        #   @param [Boolean] with_aliases if true, aliases defined in self that
        #     point to types ending up in the minimal registry will be copied
        #   @return [TypeStore::Registry] the registry that allows to define the
        #     named type
        #
        # @overload minimal(auto_types, with_aliases = true)
        #   @param [TypeStore::Registry] auto_types a registry containing the
        #     types that are not necessary in the result
        #   @param [Boolean] with_aliases if true, aliases defined in self that
        #     point to types ending up in the minimal registry will be copied
        #   @return [TypeStore::Registry] the registry that allows to define all
        #     types of self that are not in auto_types. Note that it may contain
        #     types that are in the auto_types registry, if they are needed to
        #     define some other type
	def minimal(type, with_aliases = true)
	    do_minimal(type, with_aliases)
	end

        # Creates a new registry by loading a TypeStore XML file
        #
        # @see Registry#merge_xml
        def self.from_xml(xml)
            reg = TypeStore::Registry.new
            reg.merge_xml(xml)
            reg
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
            if !block_given?
                enum_for(:each, filter, options)
            else
                each_type(filter, with_aliases, &block)
            end
        end
        include Enumerable

        # Tests for the presence of a type by its name
        #
        # @param [String] name the type name
        # @return [Boolean] true if this registry contains a type named like
        #   this
        def include?(name)
            includes?(name)
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
                raise "Cannot guess file type for #{file}: unknown extension '#{ext}'"
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
        def self.handler_for(file, kind = 'auto')
	    file = File.expand_path(file)
            if !kind || kind == 'auto'
                kind    = Registry.guess_type(file)
            end
            if handler = TYPE_HANDLERS[kind]
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
        def import(file, kind = 'auto', options = {})
	    file = File.expand_path(file)

            handler = Registry.handler_for(file, kind)
            if handler.respond_to?(:call)
                return handler.call(self, file, kind, options)
            else
                kind = handler
            end

            do_merge = 
                if options.has_key?('merge') then options.delete('merge')
                elsif options.has_key?(:merge) then options.delete(:merge)
                else true
                end

            options = Registry.format_options(options)

            do_import(file, kind, do_merge, options)
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
            types.each do |t|
                t.resized_type(typemap)
            end
        end

	# Exports the registry in the provided format, into a Ruby string. The
	# following formats are allowed as +format+:
	# 
	# +tlb+:: TypeStore's own XML format
	# +idl+:: CORBA IDL
	# 
	# +options+ is an option hash, which is export-format specific. See the C++
	# documentation of each exporter for more information.
	def export(kind, options = {})
            options = Registry.format_options(options)
            do_export(kind, options)
	end

        # Export the registry into TypeStore's own XML format
        def to_xml
            export('tlb')
        end

        # Helper class for Registry#create_compound
        class CompoundBuilder
            # The compound type being built
            attr_reader :type
            # The offset for the next field
            attr_reader :current_size

            def initialize(name, registry, size = nil)
                @current_size = 0
                @type = CompoundType.new_submodel(typename: name, registry: registry, size: size)
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
            def add(field_name, field_type, offset: current_size)
                field = type.add(field_name.to_s, field_type, offset: offset)
                @current_size = [current_size, field.offset + field.type.size].max
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

        def register(type, name: type.name)
            if types.has_key?(type.name)
                raise DuplicateType, "attempting to redefine the existing type #{type.name}"
            end
            require 'pry'
            if !name
                binding.pry
            end
            if name[0,1] == '/'
                types[name] = type
                types[name[1..-1]] = type
            else
                types[name] = type
                types["/#{name}"] = type
            end
            type
        end

        def create_null(name)
            register(Type.new_submodel(name: name, null: true))
        end

        # Create a type of unspecified model (usually for nul/opaque types)
        def create_type(name, **options)
            register(Type.new_submodel(typename: name, registry: self, **options))
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
        def create_compound(name, _size = nil, size: nil)
            size ||= _size
            recorder = CompoundBuilder.new(name, self, size)
            yield(recorder) if block_given?
            recorder.build
        end

        # Creates a new container type on this registry
        #
        # @param [String] container_type the name of the container type
        # @param [String,Type] element_type the type of the container elements,
        #   either as a type or as a type name
        #
        # @example create a new std::vector type
        #   registry.create_container "/std/vector", "/my/Container"
        def create_container(container_model, element_type, _size = nil, typename: nil, size: nil)
            if container_model.respond_to?(:to_str)
                container_model = ContainerType.from_name(container_model)
            end
            element_type = validate_type_argument(element_type)

            size ||= _size
            typename ||= "#{container_model.name}<#{element_type.name}>"
            size = nil if size == 0
            size ||= container_model.size

            container_t = container_model.
                new_submodel(registry: self, typename: typename,
                             deference: element_type, size: size)
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
        def create_array(element_type, length = 0, _size = nil, size: nil, typename: nil)
            # For backward compatibility with typelib
            size ||= _size
            size = nil if size == 0

            element_type = validate_type_argument(element_type)
            typename ||= "#{element_type.name}[#{length}]"
            size     ||= element_type.size * length
            array_t = ArrayType.new_submodel(deference: element_type, typename: typename, registry: self,
                                   length: length, size: size)
            array_t.register
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

        def alias(new_name, old_type)
            register(validate_type_argument(old_type), name: new_name)
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
                create_array(build($1), length: Integer($2), size: size, typename: typename)
            elsif typename =~ />$/
                namespace, basename = TypeStore.split_typename(typename)
                container_t_name, arguments = TypeStore.parse_template(basename)
                create_container(container_t, build(arguments[0]), typename: typename, size: size)
            else
                raise e, "#{e.message}, and it cannot be built", e.backtrace
            end
        end

        # Helper class to build new enumeration types
        class EnumBuilder
            # The type being built
            attr_reader :type
            # The value for the next symbol
            attr_reader :current_value

            def initialize(name, registry, size)
                @current_value = 0
                @type = EnumType.new_submodel(typename: name, registry: registry, size: size)
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
        def create_enum(name, size = 0)
            recorder = EnumBuilder.new(name, self, size)
            yield(recorder)
            recorder.build
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
