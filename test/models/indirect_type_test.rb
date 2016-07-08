require 'test_helper'

module ModelKit::Types
    module Models
        describe IndirectType do
            it "has a name" do
                assert_equal "ModelKit::Types::IndirectType", ModelKit::Types::IndirectType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::IndirectType.metadata
            end
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
                it "sets fixed_buffer_size? to true if the deference'd type has a fixed buffer size" do
                    t0 = ModelKit::Types::Type.new_submodel(opaque: true)
                    flexmock(t0).should_receive(:fixed_buffer_size?).and_return(true)
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert t.fixed_buffer_size?
                end
                it "sets fixed_buffer_size? to false if the deference'd type does not have a fixed buffer size" do
                    t0 = ModelKit::Types::Type.new_submodel(opaque: true)
                    flexmock(t0).should_receive(:fixed_buffer_size?).and_return(false)
                    t  = ModelKit::Types::IndirectType.new_submodel(deference: t0)
                    assert !t.fixed_buffer_size?
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

