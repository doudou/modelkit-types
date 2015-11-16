module ModelKit::Types
    # Base class for numeric types
    class NumericType < Type
        extend Models::NumericType

        # (see Type#to_simple_value)
        def to_simple_value(options = Hash.new)
            v = to_ruby
            return v if !options[:special_float_values]
            return v if self.class.integer?

            if options[:special_float_values] == :string
                if v.nan?
                    "NaN"
                elsif v.infinite?
                    if v > 0 then "Infinity"
                    else "-Infinity"
                    end
                else v
                end
            elsif options[:special_float_values] == :nil
                if v.nan? || v.infinite?
                    nil
                else v
                end
            else raise ArgumentError, ":special_float_values can only either be :string or :nil, found #{options[:special_float_values].inspect}"
            end
        end
    end
end

