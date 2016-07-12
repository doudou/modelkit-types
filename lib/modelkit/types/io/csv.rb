module ModelKit::Types
    module IO
        # Export a value into a CSV format
        #
        # Note that this is very basic: it exports the values in order, separated by
        # commas. There is no optimization, and no attempt to "align" sets of values
        class CSV
            def self.flatten(value)
                case value
                when NumericType, EnumType, CharacterType
                    [value.to_ruby]
                when CompoundType
                    value.each_field.flat_map { |field_n, field_v| flatten(field_v) }
                when ArrayType, ContainerType
                    value.flat_map { |v| flatten(v) }
                else
                    raise ArgumentError, "do not know how to convert #{value.class.superclass} to CSV"
                end
            end

            def self.export(value)
                flatten(value).map(&:to_s).join(",")
            end

            def self.flatten_type(type)
                if type <= NumericType || type <= EnumType || type <= CharacterType
                    [""]
                elsif type <= CompoundType
                    type.each.flat_map do |field|
                        flattened_field = flatten_type(field.type)
                        flattened_field.map { |field_description| ".#{field.name}#{field_description}" }
                    end
                elsif type <= ArrayType || type <= ContainerType
                    flattened_element = flatten_type(type.deference)
                    flattened_element.map { |field_description| "[]#{field_description}" }
                else
                    raise ArgumentError, "do not know how to convert #{type.superclass} to CSV"
                end
            end

            def self.export_type(type)
                flatten_type(type).join(",")
            end
        end
    end
end
