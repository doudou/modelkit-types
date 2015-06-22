module TypeStore
    module Models
        module ArrayType
            include Models::IndirectType

            def find_custom_convertions(conversion_set)
                generic_array_id = deference.name + '[]'
                super(conversion_set) +
                    super(conversion_set, generic_array_id)
            end

            def subclass_initialize
                super

                convert_from_ruby Array do |value, expected_type|
                    if value.size != expected_type.length
                        raise ArgumentError, "expected an array of size #{expected_type.length}, got #{value.size}"
                    end

                    t = expected_type.new
                    value.each_with_index do |el, i|
                        t[i] = el
                    end
                    t
                end
            end

            def extend_for_custom_convertions
                if deference.contains_converted_types?
                    self.contains_converted_types = true

                    # There is a custom convertion on the elements of this array. We
                    # have to convert to a Ruby array once and for all
                    #
                    # This can be *very* costly for big arrays
                    #
                    # Note that it is overriden by convertions that are explicitely
                    # defined for this type (i.e. that reference this type by name)
                    convert_to_ruby Array do |value|
                        # Convertion is done by value#each directly
                        converted = value.map { |v| v }
                        def converted.dup
                            map(&:dup)
                        end
                        converted
                    end
                end

                # This is done last so that convertions to ruby that refer to this
                # type by name can override the default convertion above
                super
            end

            # Returns the pointed-to type (defined for consistency reasons)
            def [](index); deference end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { 'name' => TypeName,
            #      'class' => NameOfTypeClass, # CompoundType, ...
            #      'length' => LengthOfArrayInElements,
            #      # The content of 'element' is controlled by the :recursive option
            #      'element' => DescriptionOfArrayElement,
            #      # Only if :layout_info is true
            #      'size' => SizeOfTypeInBytes 
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:length] = length
                info[:element] =
                    if options[:recursive]
                        deference.to_h(options)
                    else
                        deference.to_h_minimal(options)
                    end
                info
            end

            def ruby_convertion_candidates_on(ruby_mappings)
                super + (ruby_mappings.from_array_basename[deference.name] || Array.new)
            end
        end
    end
end

