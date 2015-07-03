module TypeStore
    module Models
        module EnumType
            include Type

            # Mapping from a numerical value to the symbol it represents
            attr_reader :value_to_symbol

            # Mapping from a symbol to the numerical value it represents
            attr_reader :symbol_to_value

            def initialize_base_class
                super
                self.name = "TypeStore::EnumType"
            end

            def ==(other)
                super && symbol_to_value == other.symbol_to_value
            end

            def setup_submodel(submodel, registry: self.registry, typename: nil, size: 0, opaque: false, null: false, &block)
                super
                submodel.instance_variable_set(:@value_to_symbol, Hash.new)
                submodel.instance_variable_set(:@symbol_to_value, Hash.new)
            end

            def copy_to(submodel, **options)
                model = super
                symbol_to_value.each do |sym, v|
                    model.add(sym, v)
                end
                model
            end

            # Add a new symbol to self
            def add(symbol, value)
                symbol, value = symbol.to_sym, Integer(value)
                value_to_symbol[value] = symbol
                symbol_to_value[symbol] = value
            end

            def validate_merge(type)
                super
                symbol_to_value = self.symbol_to_value.dup
                type.symbol_to_value.merge(symbol_to_value) do |sym, type_v, v|
                    if type_v != v
                        raise MismatchingEnumSymbolsError, "symbol #{sym} has value #{type_v} in #{type} and #{v} in #{self}"
                    end
                end
            end

            def merge(type)
                super
                @symbol_to_value = type.symbol_to_value.merge(symbol_to_value)
                @value_to_symbol = type.value_to_symbol.merge(value_to_symbol)
                self
            end

            # Returns the value of a symbol
            #
            # @param [#to_sym] symbol
            # @return [Integer] the value of symbol
            # @raise [ArgumentError] if symbol is not part of this enumeration
            def value_of(symbol)
                if value = symbol_to_value[symbol.to_sym]
                    value
                else
                    raise ArgumentError, "#{self} has not value for #{symbol}"
                end
            end

            # Returns the symbol that has this value
            #
            # If there is more than one symbol, one from all of them is picked
            #
            # @param [Integer] value
            # @return [Symbol] the symbol for value
            # @raise [ArgumentError] if there is no symbol with this value
            def name_of(value)
                if symbol = value_to_symbol[Integer(value)]
                    symbol
                else
                    raise ArgumentError, "#{self} has no symbol with value #{value}"
                end
            end

            # Enumerate the symbol/value pairs
            #
            # @yieldparam [Symbol] symbol
            # @yieldparam [Integer] value
            def each(&block)
                symbol_to_value.each(&block)
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
                info[:values] = symbol_to_value.map do |n, v|
                    Hash[name: n.to_s, value: v]
                end
                info
            end

            def pretty_print(pp, verbose = false) # :nodoc:
                super
		pp.text '{'
                pp.nest(2) do
                    keys = self.keys.sort_by(&:last)
		    pp.breakable
                    pp.seplist(symbol_to_value) do |keydef|
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

