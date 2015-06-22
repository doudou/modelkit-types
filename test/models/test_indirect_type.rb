require 'typestore/test'

module TypeStore
    module Models
        describe IndirectType do
            describe "#new_submodel" do
                it "sets the type's deference property" do
                    t0 = TypeStore::Type.new_submodel
                    t  = TypeStore::IndirectType.new_submodel(deference: t0)
                    assert_same t0, t.deference
                end
                it "adds the deference type to the type's direct dependencies" do
                    t0 = TypeStore::Type.new_submodel
                    t  = TypeStore::IndirectType.new_submodel(deference: t0)
                    assert_equal [t0].to_set, t.direct_dependencies
                end
                it "sets contains_opaques? to true if the deference'd type contains opaques" do
                    t0 = TypeStore::Type.new_submodel
                    t0.contains_opaques = true
                    t  = TypeStore::IndirectType.new_submodel(deference: t0)
                    assert t.contains_opaques?
                end
                it "sets contains_opaques? to true if the deference'd type is opaque" do
                    t0 = TypeStore::Type.new_submodel(opaque: true)
                    t  = TypeStore::IndirectType.new_submodel(deference: t0)
                    assert t.contains_opaques?
                end
            end
        end
    end
end

