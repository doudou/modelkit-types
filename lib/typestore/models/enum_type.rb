module TypeStore
    module Models
        module EnumType
            include Type

            def from_ruby(value)
                v = new
                v.typelib_from_ruby(value)
                v
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { 'name' => TypeName,
            #      'class' => 'EnumType',
            #      # The content of 'element' is controlled by the :recursive option
            #      'values' => [{ 'name' => NameOfValue,
            #                     'value' => ValueOfValue }],
            #      # Only if :layout_info is true
            #      'size' => SizeOfTypeInBytes 
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:values] = keys.map do |n, v|
                    Hash[name: n, value: v]
                end
                info
            end

            def pretty_print(pp, verbose = false) # :nodoc:
                super
		pp.text '{'
                pp.nest(2) do
                    keys = self.keys.sort_by(&:last)
		    pp.breakable
                    pp.seplist(keys) do |keydef|
                        if verbose
                            pp.text keydef.join(" = ")
                        else
                            pp.text keydef[0]
                        end
                    end
                end
		pp.breakable
		pp.text '}'
            end
        end
    end
end

