module TypeStore
    class RubyDomainConverter
        def self.identity
            @identity ||= Identity.new
        end

        def self.build(type)
            Class.new(RubyDomainConverter) do
                singleton_class.class_eval do
                    define_method(:name) { "TypeStore::RubyDomainConverter(#{type.name})" }
                end

                if type.needs_convertion_to_ruby?
                    convertion_block = type.convertion_to_ruby.block
                    define_method(:to_ruby) do |value|
                        convertion_block.call(value)
                    end
                end

                if type.needs_convertion_from_ruby?
                    conversions = type.convertions_from_ruby
                    define_method(:from_ruby) do |value|
                        if converted = try_convertion_from_typestore_value(value)
                            return converted
                        elsif block = conversions[value.class]
                            return block.call(value, type)
                        else
                            super
                        end
                    end
                end
            end
        end

        def try_convertion_from_typestore_value(arg, type)
            return if !(arg.class < Type)
            arg.apply_changes_from_converted_types

            if arg.kind_of?(type)
                return arg
            elsif arg.class.casts_to?(expected_type)
                return arg.cast(expected_type)
            end
        end

        def to_ruby(value)
            value
        end

        def from_ruby(value)
            if value.class != type
                value_typename = value.class.name
                expected_typename = expected_type.name
                if value_typename != expected_typename
                    raise UnknownConversionRequested.new(value, expected_type), "types differ and there are not convertions from one to the other: #{value_typename} <-> #{expected_typename}"
                else
                    raise ConversionToMismatchedType.new(arg, expected_type), "requested conversions between two types named the same (#{expected_typename} that have different definitions"
                end
            end
            value
        end
    end
end
