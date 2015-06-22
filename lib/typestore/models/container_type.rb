module TypeStore
    module Models
        module ContainerType
            include IndirectType

            def subclass_initialize
                super if defined? super

                if random_access?
                    include RandomAccessContainer
                end

                convert_from_ruby Array do |value, expected_type|
                    t = expected_type.new
                    t.concat(value)
                    t
                end
                convert_from_ruby DeepCopyArray do |value, expected_type|
                    t = expected_type.new
                    t.concat(value)
                    t
                end
            end

            def extend_for_custom_convertions
                if deference.contains_converted_types?
                    self.contains_converted_types = true

                    # There is a custom convertion on the elements of this
                    # container. We have to convert to a Ruby array once and for all
                    #
                    # This can be *very* costly for big containers
                    #
                    # Note that it is called before super() so that it gets
                    # overriden by convertions that are explicitely defined for this
                    # type (i.e. that reference this type by name)
                    convert_to_ruby Array do |value|
                        # Convertion is done by #map
                        result = DeepCopyArray.new
                        for v in value
                            result << v
                        end
                        result
                    end
                end

                # This is done last so that convertions to ruby that refer to this
                # type by name can override the default convertion above
                super if defined? super

                if deference.needs_convertion_to_ruby?
                    include ConvertToRuby
                end
                if deference.needs_convertion_from_ruby?
                    include ConvertFromRuby
                end
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { name: TypeName,
            #      class: NameOfTypeClass, # CompoundType, ...
            #       # The content of 'element' is controlled by the :recursive option
            #      element: DescriptionOfArrayElement,
            #      size: SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:element] =
                    if options[:recursive]
                        deference.to_h(options)
                    else
                        deference.to_h_minimal(options)
                    end
                info
            end

            def ruby_convertion_candidates_on(ruby_mappings)
                super + (ruby_mappings.from_containre_basename[container_kind] || Array.new)
            end
        end
    end
end

