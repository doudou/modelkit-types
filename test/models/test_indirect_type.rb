require 'modelkit/types/test'

module ModelKit::Types
    module Models
        describe IndirectType do
            describe "#new_submodel" do
                it "sets the type's deference property" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert_same t0, t.deference
                end
                it "adds the deference type to the type's direct dependencies" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert_equal [t0].to_set, t.direct_dependencies
                end
                it "sets contains_opaques? to true if the deference'd type contains opaques" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t0.contains_opaques = true
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert t.contains_opaques?
                end
                it "sets contains_opaques? to true if the deference'd type is opaque" do
                    t0 = ModelKit::Types::Type.new_submodel(opaque: true)
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert t.contains_opaques?
                end
                it "sets contains_converted_types? to true if the deference'd type contains converted types itself" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t0.contains_converted_types = true
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert t.contains_converted_types?
                end
                it "sets contains_converted_types? to true if the deference'd type needs convertions" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t0.convert_to_ruby(Array) { Array.new }
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert t.contains_converted_types?
                end
            end

            describe "#validate_merge" do
                it "passes if the deference'd typenames are equal" do
                    t0 = ModelKit::Types::Type.new_submodel typename: 't0'
                    t1 = ModelKit::Types::Type.new_submodel typename: 't0'
                    i0 = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    i1 = ModelKit::Types::IndirectType.new_submodel(deference: t1)
                    i0.validate_merge(i1)
                end

                it "raises if the deference'd typename differ" do
                    t0 = ModelKit::Types::Type.new_submodel typename: 't0'
                    t1 = ModelKit::Types::Type.new_submodel typename: 't1'
                    i0 = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    i1 = ModelKit::Types::IndirectType.new_submodel(deference: t1)
                    assert_raises(MismatchingDeferencedTypeError) { i0.validate_merge(i1) }
                end
            end
        end
    end
end

