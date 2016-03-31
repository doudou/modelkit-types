module ModelKit::Types
    module Models
        module ArrayType
            include Models::IndirectType

            # Length of the array, in the number of elements
            attr_accessor :length

            def initialize_base_class
                super
                self.name = "ModelKit::Types::ArrayType"
            end

            def ==(other)
                super && length == other.length
            end

            def casts_to?(type)
                super || deference == type
            end

            def setup_submodel(submodel, deference: nil, length: 0, registry: self.registry, typename: nil,
                               size: deference.size * length, opaque: false, null: false)
                super(submodel, deference: deference, registry: registry, typename: typename, size: size, opaque: opaque, null: null)

                submodel.length = length
            end

            def copy_to(registry, **options)
                super(registry, length: length, **options)
            end

            # Apply a set of type-resize mappings
            def apply_resize(typemap)
                if new_size = typemap[deference]
                    new_size * length
                end
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
        end
    end
end

