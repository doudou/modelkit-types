require 'set'
require 'base64'
require 'enumerator'
require 'utilrb/logger'
require 'utilrb/object/singleton_class'
require 'utilrb/kernel/options'
require 'utilrb/module/attr_predicate'
require 'utilrb/module/const_defined_here_p'
require 'facets/string/camelcase'

# TypeStore allows to do two things:
#
# * represent types (it is a <i>type system</i>). These representations will be
#   referred to as _types_ in the documentation.
# * manipulate in-memory values represented by these types. These are
#   referred to as _values_ in the documentation.
#
# As types may depend on each other (for instance, a structure depend on the
# types used to define its fields), TypeStore maintains a consistent set of types
# in a so-called registry. Types in a registry can only refer to other types in
# the same registry.
#
# On the Ruby side, a _type_ is represented as a subclass of one of the
# specialized subclasses of TypeStore::Type (depending of what kind of type it
# is). I.e.  a _type_ itself is a class, and the methods that are available on
# Type objects are the singleton methods of the Type class (or its specialized
# subclasses).  Then, a value is simply an instance of that same class.
#
# TypeStore specializes for the following kinds of types:
#
# * structures and unions (TypeStore::CompoundType)
# * static length arrays (TypeStore::ArrayType)
# * dynamic containers (TypeStore::ContainerType)
# * mappings from strings to numerical values (TypeStore::EnumType)
#
# In other words:
#
#   registry = <load the registry>
#   type  = registry.get 'A' # Get the Type subclass that represents the A
#                            # structure
#   value = type.new         # Create an uninitialized value of type A
#
#   value.class == type # => true
#   type.ancestors # => [type, TypeStore::CompoundType, TypeStore::Type]
#
# Each class representing a type can be further specialized using
# TypeStore.specialize_model and TypeStore.specialize
# 
module TypeStore
    extend Logger::Root('TypeStore', Logger::WARN)

    class << self
	# If true (the default), TypeStore will load its type plugins. Otherwise,
        # it will not
        attr_predicate :load_plugins, true

        # Controls whether TypeStore should issue warnings when helper methods
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

    # The namespace separator character used by TypeStore
    NAMESPACE_SEPARATOR = '/'

    # Returns the basename part of +name+, i.e. the type name
    # without the namespace part.
    #
    # See also Type.basename
    def self.basename(name, separator = NAMESPACE_SEPARATOR)
        split_typename(name, separator).last
    end

    # Returns the namespace part of +name+.  If +separator+ is
    # given, the namespace components are separated by it, otherwise,
    # the default of TypeStore::NAMESPACE_SEPARATOR is used. If nil is
    # used as new separator, no change is made either.
    def self.namespace(name, separator = NAMESPACE_SEPARATOR, remove_leading = false)
        parts = split_typename(name, separator)
        ns = parts[0, parts.size - 1].join(separator)
        if !remove_leading
            "#{separator}#{ns}#{separator}"
        else "#{ns}#{separator}"
        end
    end

    # Splits a typename into its consistuent
    #
    # @return [Array<String>] each string is a namespace leading to the
    #   basename. The last element is the basename itself
    def self.split_typename(name, separator = NAMESPACE_SEPARATOR)
        tokens = typename_tokenizer(name)
        build_typename_parts(tokens, namespace_separator: separator)
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
            suffix =~ /^([^<\/,>]*)/
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
                TypeStore.warn "NOT defining #{candidates.join(", ")} on #{msg_name} as it would overload a necessary method"
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
            TypeStore.warn "NOT defining #{name} on #{msg_name} as it would overload a necessary method"
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
require 'typestore/exceptions'
require 'typestore/ruby_mapping_specialization'
require 'typestore/type_specialization_module'
require 'typestore/specializations'
require 'typestore/metadata'

require 'typestore/models/path'
require 'typestore/models/accessor'

require 'typestore/models/type'
require 'typestore/type'
require 'typestore/models/numeric_type'
require 'typestore/numeric_type'
require 'typestore/models/indirect_type'
require 'typestore/indirect_type'
require 'typestore/models/opaque_type'
require 'typestore/opaque_type'
require 'typestore/models/pointer_type'
require 'typestore/pointer_type'
require 'typestore/models/array_type'
require 'typestore/array_type'
require 'typestore/models/compound_type'
require 'typestore/compound_type'
require 'typestore/models/enum_type'
require 'typestore/enum_type'
require 'typestore/models/container_type'
require 'typestore/container_type'

require 'typestore/registry'
require 'typestore/registry_export'

class Class
    def to_ruby(value)
        value
    end
end

module TypeStore
    # Generic method that converts a TypeStore value into the corresponding Ruby
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
end

# Finally, set guard types on the root classes
module TypeStore
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
    class OpaqueType
        initialize_base_class
    end
    class PointerType
        initialize_base_class
    end
end

