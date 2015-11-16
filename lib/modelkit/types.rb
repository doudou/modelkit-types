require 'set'
require 'base64'
require 'enumerator'
require 'utilrb/logger'
require 'utilrb/module/attr_predicate'
require 'utilrb/hash/map_key'
require 'facets/string/camelcase'

require 'modelkit/types/version'

# ModelKit::Types allows to do two things:
#
# * represent types (it is a <i>type system</i>). These representations will be
#   referred to as _types_ in the documentation.
# * manipulate in-memory values represented by these types. These are
#   referred to as _values_ in the documentation.
#
# As types may depend on each other (for instance, a structure depend on the
# types used to define its fields), ModelKit::Types maintains a consistent set of types
# in a so-called registry. Types in a registry can only refer to other types in
# the same registry.
#
# On the Ruby side, a _type_ is represented as a subclass of one of the
# specialized subclasses of ModelKit::Types::Type (depending of what kind of type it
# is). I.e.  a _type_ itself is a class, and the methods that are available on
# Type objects are the singleton methods of the Type class (or its specialized
# subclasses).  Then, a value is simply an instance of that same class.
#
# ModelKit::Types specializes for the following kinds of types:
#
# * structures and unions (ModelKit::Types::CompoundType)
# * static length arrays (ModelKit::Types::ArrayType)
# * dynamic containers (ModelKit::Types::ContainerType)
# * mappings from strings to numerical values (ModelKit::Types::EnumType)
#
# In other words:
#
#   registry = <load the registry>
#   type  = registry.get 'A' # Get the Type subclass that represents the A
#                            # structure
#   value = type.new         # Create an uninitialized value of type A
#
#   value.class == type # => true
#   type.ancestors # => [type, ModelKit::Types::CompoundType, ModelKit::Types::Type]
#
# Each class representing a type can be further specialized using
# ModelKit::Types.specialize_model and ModelKit::Types.specialize
# 
module ModelKit::Types
    extend Logger::Root('ModelKit::Types', Logger::WARN)

    class << self
	# If true (the default), ModelKit::Types will load its type plugins. Otherwise,
        # it will not
        attr_predicate :load_plugins, true

        # Controls whether ModelKit::Types should issue warnings when helper methods
        # (such as the field accessor methods in
        # {Typelib::Models::CompoundType}) cannot be defined because of clashes
        # with existing methods
        #
        # The default is to warn (true)
        attr_predicate :warn_about_helper_method_clashes?, true

        # Whether the local architecture is big endian
        attr_predicate :big_endian?
    end
    @load_plugins = true
    @warn_about_helper_method_clashes = true
    @big_endian = ([1].pack("N") == [1].pack("I"))

    # The namespace separator character used by ModelKit::Types
    NAMESPACE_SEPARATOR = '/'

    # Returns the basename part of +name+, i.e. the type name
    # without the namespace part.
    #
    # See also Type.basename
    def self.basename(name, separator = NAMESPACE_SEPARATOR)
        return split_typename(name, separator).last
    end

    # Returns the namespace part of +name+.  If +separator+ is
    # given, the namespace components are separated by it, otherwise,
    # the default of ModelKit::Types::NAMESPACE_SEPARATOR is used. If nil is
    # used as new separator, no change is made either.
    def self.namespace(name, separator = NAMESPACE_SEPARATOR, remove_leading = false)
        return split_typename(name, separator, remove_leading).first
    end

    # Splits a typename into its namespace and basename
    #
    # @return [(String,String)] the type's basename and 
    def self.split_typename(name, separator = NAMESPACE_SEPARATOR, remove_leading = false)
        parts = typename_parts(name, separator)
        basename = parts.pop

        ns = parts.join(separator)
        if ns.empty?
            return separator, basename
        elsif !remove_leading
            return "#{separator}#{ns}#{separator}", basename
        else
            return "#{ns}#{separator}", basename
        end
    end

    # Splits a typename into its consistuent
    #
    # @return [Array<String>] each string is a namespace leading to the
    #   basename. The last element is the basename itself
    def self.typename_parts(name, separator = NAMESPACE_SEPARATOR)
        tokens = typename_tokenizer(name)
        build_typename_parts(tokens, namespace_separator: separator)
    end

    # Splits a type basename into its main name and (possible) template
    # arguments
    def self.parse_template(type_basename)
        if type_basename =~ /^([^<]+)(?:<(.*)>)?$/
            basename, raw_arguments = $1, $2
            if !raw_arguments
                return basename, []
            end
        else
            raise ArgumentError, "#{type_basename} does not look like a valid typename"
        end

        arguments = []
        tokens = typename_tokenizer(raw_arguments)
        current = []
        level = 0
        while !tokens.empty?
            tk = tokens.shift
            if tk == ',' && level == 0
                arguments << current.join("")
                current = []
                next
            end

            current << tk
            if tk == '<'
                level += 1
            elsif tk == '>'
                level -= 1
            end
        end

        if !current.empty?
            arguments << current.join("")
        end
        return basename, arguments
    end

    # Validates that the given name is a canonical ModelKit::Types type name
    def self.validate_typename(name, absolute: true)
        tokens = typename_tokenizer(name)
        if absolute && (tokens.first != NAMESPACE_SEPARATOR)
            raise InvalidTypeNameError, "expected #{name} to have a leading #{NAMESPACE_SEPARATOR}"
        end

        in_array = false
        template_level = 0
        while !tokens.empty?
            if in_array
                case tk = tokens.shift
                when /^\d+$/
                when "]"
                    in_array = false
                else
                    raise InvalidTypeNameError, "found #{tk} in array definition"
                end
            else
                case tk = tokens.shift
                when NAMESPACE_SEPARATOR
                    if (tk = tokens.first) && tk !~ /[a-zA-Z]/
                        raise InvalidTypeNameError, "found #{tk} after /, expected a letter"
                    end
                when "["
                    in_array = true
                when "<"
                    template_level += 1
                    if (tk = tokens.first) && tk !~ /[\-0-9\/]/
                        raise InvalidTypeNameError, "found #{tk} after <, expected a type name or a number"
                    end
                when ","
                    if (tk = tokens.first) && tk !~ /[\-0-9\/]/
                        raise InvalidTypeNameError, "found #{tk} after ,, expected a type name or a number"
                    end
                when ">"
                    if template_level == 0
                        raise InvalidTypeNameError, "found > without matching opening <"
                    end
                    template_level -= 1
                    if (tk = tokens.first) && tk !~ /[>,\/\[]/
                        raise InvalidTypeNameError, "found #{tk} after >"
                    end
                when /^[\w ]+$/
                else
                    raise InvalidTypeNameError, "found #{tk}, expected alphanumeric characters or _"
                end
            end
        end
        if template_level != 0
            raise InvalidTypeNameError, "missing closing >"
        end
        
    rescue InvalidTypeNameError => e
        raise e, "#{name} is not a valid#{' absolute' if absolute} type name: #{e.message}", e.backtrace
    end

    def self.build_typename_parts(tokens, namespace_separator: NAMESPACE_SEPARATOR)
        level = 0
        parts = []
        current = []
        while !tokens.empty?
            case tk = tokens.shift
            when "/"
                if level == 0
                    if !current.empty?
                        parts << current
                        current = []
                    end
                else
                    current << namespace_separator
                end
            when "<"
                level += 1
                current << "<"
            when ">"
                level -= 1
                current << ">"
            else
                current << tk
            end
        end
        if !current.empty?
            parts << current
        end

        return parts.map { |p| p.join("") }
    end

    def self.typename_tokenizer(name)
        suffix = name
        result = []
        while !suffix.empty?
            suffix =~ /^([^<\/,>\[\]]*)/
            match = $1.strip
            if !match.empty?
                result << match
            end
            char   = $'[0, 1]
            suffix = $'[1..-1]

            break if !suffix

            result << char
        end
        result
    end

    def self.can_overload_method?(defined_on, reference, name,
                                  message: "instances of #{reference_class.name}",
                                  allowed_overloadings: Models::Type::ALLOWED_OVERLOADINGS,
                                  with_raw: true)

        candidates = [n, "#{n}="]
        if with_raw
            candidates.concat(["raw_#{n}", "raw_#{n}="])
        end
        candidates.all? do |method_name|
            if !reference_class.method_defined?(method_name) || allowed_overloadings.include?(method_name)
                true
            elsif warn_about_helper_method_clashes?
                msg_name ||= "instances of #{reference_class.name}"
                ModelKit::Types.warn "NOT defining #{candidates.join(", ")} on #{msg_name} as it would overload a necessary method"
                false
            end
        end
    end

    def self.filter_methods_that_should_not_be_defined(on, reference_class, names, allowed_overloadings, msg_name, with_raw)
        names.find_all do |n|
        end
    end

    def self.define_method_if_possible(on, reference_class, name, allowed_overloadings = [], msg_name = nil, &block)
        if !reference_class.method_defined?(name) || allowed_overloadings.include?(name)
            on.send(:define_method, name, &block)
            true
        elsif warn_about_helper_method_clashes?
            msg_name ||= "instances of #{reference_class.name}"
            ModelKit::Types.warn "NOT defining #{name} on #{msg_name} as it would overload a necessary method"
            false
        end
    end

    # Set of classes that have a #dup method but on which dup is forbidden
    DUP_FORBIDDEN = [TrueClass, FalseClass, Fixnum, Float, Symbol]

    def self.load_plugins
        if !ENV['TYPESTORE_RUBY_PLUGIN_PATH'] || (@@typestore_plugin_path == ENV['TYPESTORE_RUBY_PLUGIN_PATH'])
            return
        end

        ENV['TYPESTORE_RUBY_PLUGIN_PATH'].split(':').each do |dir|
            specific_file = File.join(dir, "typestore_plugin.rb")
            if File.exists?(specific_file)
                require specific_file
            else
                Dir.glob(File.join(dir, '*.rb')) do |file|
                    require file
                end
            end
        end

        @@typestore_plugin_path = ENV['TYPESTORE_RUBY_PLUGIN_PATH'].dup
    end
    @@typestore_plugin_path = nil
end

# Type models
require 'metaruby'
require 'modelkit/types/exceptions'
require 'modelkit/types/ruby_specialization_mapping'
require 'modelkit/types/type_specialization_module'
require 'modelkit/types/specialization_manager'
require 'modelkit/types/metadata'
require 'modelkit/types/deep_copy_array'

require 'modelkit/types/models/path'
require 'modelkit/types/models/accessor'

require 'modelkit/types/models/type'
require 'modelkit/types/type'
require 'modelkit/types/models/numeric_type'
require 'modelkit/types/numeric_type'
require 'modelkit/types/models/indirect_type'
require 'modelkit/types/indirect_type'
require 'modelkit/types/models/array_type'
require 'modelkit/types/array_type'
require 'modelkit/types/models/compound_type'
require 'modelkit/types/compound_type'
require 'modelkit/types/models/enum_type'
require 'modelkit/types/enum_type'
require 'modelkit/types/models/container_type'
require 'modelkit/types/container_type'

require 'modelkit/types/registry'
require 'modelkit/types/registry_export'
require 'modelkit/types/io/xml_exporter'
require 'modelkit/types/io/xml_importer'

class Class
    def to_ruby(value)
        value
    end
end

module ModelKit::Types
    def self.specialization_manager
        @specialization_manager ||= SpecializationManager.new
    end

    def self.specialize_model(*args, **options, &block)
        specialization_manager.specialize(*args, **options, &block)
    end

    def self.specialize(*args, **options, &block)
        specialization_manager.specialize(*args, **options, &block)
    end

    def self.convert_to_ruby(*args, **options, &block)
        specialization_manager.specialize(*args, **options, &block)
    end

    def self.convert_from_ruby(*args, **options, &block)
        specialization_manager.specialize(*args, **options, &block)
    end

    # Generic method that converts a ModelKit::Types value into the corresponding Ruby
    # value.
    def self.to_ruby(value, original_type = nil)
        (original_type || value.class).to_ruby(value)
    end

    # Proper copy of a value to another. +to+ and +from+ do not have to be from the
    # same registry, as long as the types can be casted into each other
    #
    # @return [Type] the target value
    def self.copy(to, from)
        if to.invalidated?
            raise TypeError, "cannot copy, the target has been invalidated"
        elsif from.invalidated?
            raise TypeError, "cannot copy, the source has been invalidated"
        end

        if to.respond_to?(:invalidate_changes_from_converted_types)
            to.invalidate_changes_from_converted_types
        end
        if from.respond_to?(:apply_changes_from_converted_types)
            from.apply_changes_from_converted_types
        end

        to.allocating_operation do
            do_copy(to, from)
        end
    end

    def self.compare(a, b)
        if a.respond_to?(:apply_changes_from_converted_types)
            a.apply_changes_from_converted_types
        end
        if b.respond_to?(:apply_changes_from_converted_types)
            b.apply_changes_from_converted_types
        end
        a.to_byte_array == b.to_byte_array
    end

    # Initializes +expected_type+ from +arg+, where +arg+ can either be a value
    # of expected_type, a value that can be casted into a value of
    # expected_type, or a Ruby value that can be converted into a value of
    # +expected_type+.
    def self.from_ruby(arg, expected_type)      
        if arg.respond_to?(:apply_changes_from_converted_types)
            arg.apply_changes_from_converted_types
        end

        if arg.kind_of?(expected_type)
            return arg
        elsif arg.class < Type && arg.class.casts_to?(expected_type)
            return arg.cast(expected_type)
        elsif convertion = expected_type.convertions_from_ruby[arg.class]
            converted = convertion.call(arg, expected_type)
        elsif expected_type.respond_to?(:from_ruby)
            converted = expected_type.from_ruby(arg)
        else
            if !(expected_type < NumericType) && !arg.kind_of?(expected_type)
                if arg.class.name != expected_type.name
                    raise UnknownConversionRequested.new(arg, expected_type), "types differ and there are not convertions from one to the other: #{arg.class.name} <-> #{expected_type.name}"
                else
                    raise ConversionToMismatchedType.new(arg, expected_type), "the types have the same name but different definitions: #{arg.class.name} <-> #{expected_type.name}"
                end
            end
            converted = arg
        end
        if !(expected_type < NumericType) && !converted.kind_of?(expected_type)
            raise RuntimeError, "invalid conversion of #{arg} to #{expected_type.name}"
        end
        if !converted.eql?(arg)
            converted.apply_changes_from_converted_types
        end
        converted
    end

    def self.load_plugins
        if !ENV['TYPELIB_RUBY_PLUGIN_PATH'] || (@@typelib_plugin_path == ENV['TYPELIB_RUBY_PLUGIN_PATH'])
            return
        end

        ENV['TYPELIB_RUBY_PLUGIN_PATH'].split(':').each do |dir|
            specific_file = File.join(dir, "typelib_plugin.rb")
            if File.exists?(specific_file)
                require specific_file
            else
                Dir.glob(File.join(dir, '*.rb')) do |file|
                    require file
                end
            end
        end

        @@typelib_plugin_path = ENV['TYPELIB_RUBY_PLUGIN_PATH'].dup
    end
    @@typelib_plugin_path = nil
end

# Finally, set guard types on the root classes
module ModelKit::Types
    class Type
        initialize_base_class
    end
    class NumericType
        initialize_base_class
    end
    class EnumType
        initialize_base_class
    end
    class CompoundType
        initialize_base_class
    end
    class ContainerType
        initialize_base_class
    end
    class ArrayType
        initialize_base_class
    end
    class IndirectType
        initialize_base_class
    end
end
