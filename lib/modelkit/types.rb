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
    @warn_about_helper_method_clashes = true
    @big_endian = ([1].pack("N") == [1].pack("I"))

    # The namespace separator character used by ModelKit::Types
    NAMESPACE_SEPARATOR = '/'

    # Returns the basename part of +name+, i.e. the type name
    # without the namespace part.
    #
    # See also Type.basename
    def self.basename(name, separator: NAMESPACE_SEPARATOR)
        return split_typename(name, separator: separator).last
    end

    # Returns the namespace part of +name+.  If +separator+ is
    # given, the namespace components are separated by it, otherwise,
    # the default of ModelKit::Types::NAMESPACE_SEPARATOR is used. If nil is
    # used as new separator, no change is made either.
    def self.namespace(name, separator: NAMESPACE_SEPARATOR, remove_leading: false)
        return split_typename(name, separator: separator, remove_leading: remove_leading).first
    end

    # Splits a typename into its namespace and basename
    #
    # @return [(String,String)] the type's basename and namespace
    def self.split_typename(name, separator: NAMESPACE_SEPARATOR, remove_leading: false)
        parts = typename_parts(name, separator: separator)
        if parts.empty?
            return ['/']
        end

        basename = parts.pop
        ns = parts.join(separator)
        if ns.empty?
            if remove_leading
                return '', basename
            else
                return separator, basename
            end
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
    def self.typename_parts(name, separator: NAMESPACE_SEPARATOR)
        tokens = typename_tokenizer(name)
        build_typename_parts(tokens, separator: separator)
    end

    # Splits a type basename into its main name and (possible) template
    # arguments
    def self.parse_template(type_basename, full_name: false)
        if full_name
            namespace, basename = split_typename(type_basename)
            basename, args = parse_template(basename)
            return "#{namespace}#{basename}", args
        end

        if type_basename =~ /^([^<]+)(?:<(.*)>)?$/
            basename, raw_arguments = $1, $2
            if !raw_arguments
                return basename, []
            end
        else
            raise InvalidTypeNameError, "#{type_basename} does not look like a valid typename"
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
                if level == 0
                    raise InvalidTypeNameError, "found > without matching opening <"
                end
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
        if !name.respond_to?(:to_str)
            raise InvalidTypeNameError, "type names must be strings"
        end

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
                    if (tk = tokens.first) && tk !~ /[a-zA-Z_]/
                        raise InvalidTypeNameError, "found #{tk} after /, expected a letter"
                    end
                when "["
                    in_array = true
                when "<"
                    template_level += 1
                    if (tk = tokens.first)
                        if tk =~ /^[\-0-9][0-9]*$/
                            tokens.shift
                        elsif tk !~ /^\//
                            raise InvalidTypeNameError, "found #{tk} after <, expected a type name or a number"
                        end
                    end
                when ","
                    if (tk = tokens.first)
                        if tk =~ /^[\-0-9][0-9]*$/
                            tokens.shift
                        elsif tk !~ /^\//
                            raise InvalidTypeNameError, "found #{tk} after <, expected a type name or a number"
                        end
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

    def self.build_typename_parts(tokens, separator: NAMESPACE_SEPARATOR)
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
                    current << separator
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

    # Set of classes that have a #dup method but on which dup is forbidden
    DUP_FORBIDDEN = [TrueClass, FalseClass, Fixnum, Float, Symbol]
end

# Type models
require 'metaruby'
require 'modelkit/types/exceptions'
# require 'modelkit/types/ruby_specialization_mapping'
# require 'modelkit/types/type_specialization_module'
# require 'modelkit/types/specialization_manager'
require 'modelkit/types/metadata'
require 'modelkit/types/buffer'

require 'modelkit/types/models/type'
require 'modelkit/types/type'
require 'modelkit/types/models/numeric_type'
require 'modelkit/types/numeric_type'
require 'modelkit/types/models/character_type'
require 'modelkit/types/character_type'
require 'modelkit/types/models/indirect_type'
require 'modelkit/types/indirect_type'
require 'modelkit/types/value_sequence'
require 'modelkit/types/sequence_type'
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

