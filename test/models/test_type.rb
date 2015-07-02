require 'typestore/test'

module TypeStore
    module Models
        describe Type do
            describe "#new_submodel" do
                it "inherits the registry by default" do
                    assert_same TypeStore::Type.new_submodel.registry, TypeStore::Type.registry
                end
                it "overrides the default registry" do
                    registry = Registry.new
                    assert_same registry, TypeStore::Type.new_submodel(registry: registry).registry
                end
                it "sets #name to the provided type name" do
                    assert_equal '/Test', TypeStore::Type.new_submodel(typename: '/Test').name
                end
                it "sets #size to the provided type size" do
                    assert_equal 10, TypeStore::Type.new_submodel(size: 10).size
                end
                it "sets #null? to the provided null option" do
                    assert_equal false, TypeStore::Type.new_submodel(null: false).null?
                    assert_equal true, TypeStore::Type.new_submodel(null: true).null?
                end
                it "sets #opaque? to the provided opaque option" do
                    assert_equal false, TypeStore::Type.new_submodel(opaque: false).opaque?
                    assert_equal true, TypeStore::Type.new_submodel(opaque: true).opaque?
                end
            end
            describe "#basename" do
                it "calls TypeStore.basename to extract the type's basename" do
                    flexmock(TypeStore).should_receive(:basename).with("/NS1/Bla/Test", '/').
                        and_return(ret = flexmock)
                    assert_equal ret, TypeStore::Type.new_submodel(typename: "/NS1/Bla/Test").basename
                end
            end
            describe "#namespace" do
                it "calls TypeStore.namespace to extract the type's namespace" do
                    flexmock(TypeStore).should_receive(:namespace).with("/NS1/Bla/Test", '/', false).
                        and_return(ret = flexmock)
                    assert_equal ret, TypeStore::Type.new_submodel(typename: "/NS1/Bla/Test").namespace
                end
            end
            describe "#split_typename" do
                it "calls TypeStore.split_typename to split the type's name" do
                    flexmock(TypeStore).should_receive(:split_typename).with("/NS1/Bla/Test", '/').
                        and_return(ret = flexmock)
                    assert_equal ret, TypeStore::Type.new_submodel(typename: "/NS1/Bla/Test").split_typename
                end
            end
            describe "#metadata" do
                it "always returns the same MetaData object" do
                    t = TypeStore::Type.new_submodel
                    assert_same t.metadata, t.metadata
                end
                it "returns a MetaData object" do
                    assert_kind_of MetaData, TypeStore::Type.new_submodel.metadata
                end
                it "returns the type's own MetaData object" do
                    refute_same TypeStore::Type.metadata, TypeStore::Type.new_submodel.metadata
                end
            end
            describe "XML marshalling" do
                it "marshals and unmarshals metadata" do
                    t = TypeStore::Type.new_submodel
                    t.metadata.set('k', 'v0', 'v1')
                    t = TypeStore::Registry.from_xml(t.to_xml).get(t.name)
                    assert_equal [['k', ['v0', 'v1'].to_set]], t.metadata.each.to_a
                end
            end
            describe "#merge" do
                it "merges the metadata together" do
                    t0 = TypeStore::Type.new_submodel
                    t1 = TypeStore::Type.new_submodel
                    flexmock(t0.metadata).should_receive(:merge).with(t1.metadata).once
                    t0.merge(t1)
                end
            end
            describe "#validate_merge" do
                it "passes for equivalent types" do
                    t0 = TypeStore::Type.new_submodel(typename: 't', size: 10, opaque: false, null: true)
                    t1 = TypeStore::Type.new_submodel(typename: 't', size: 10, opaque: false, null: true)
                    t0.validate_merge(t1)
                end
                it "raises InvalidMerge if the names differ" do
                    t0 = TypeStore::Type.new_submodel typename: 't0'
                    t1 = TypeStore::Type.new_submodel typename: 't1'
                    assert_raises(MismatchingTypeNameError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the supermodels differ" do
                    t0 = TypeStore::CompoundType.new_submodel
                    t1 = TypeStore::Type.new_submodel
                    assert_raises(MismatchingTypeModelError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the sizes differ" do
                    t0 = TypeStore::Type.new_submodel size: 1
                    t1 = TypeStore::Type.new_submodel size: 2
                    assert_raises(MismatchingTypeSizeError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the opaque flag differ" do
                    t0 = TypeStore::Type.new_submodel opaque: true
                    t1 = TypeStore::Type.new_submodel opaque: false
                    assert_raises(MismatchingTypeOpaqueFlagError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the null flag differ" do
                    t0 = TypeStore::Type.new_submodel null: true
                    t1 = TypeStore::Type.new_submodel null: false
                    assert_raises(MismatchingTypeNullFlagError) { t0.validate_merge(t1) }
                end
            end

            describe "#copy_to" do
                attr_reader :r0, :r1, :t0
                before do
                    @r0, @r1 = Registry.new, Registry.new
                    @t0 = r0.create_type '/Test', opaque: true, null: false, size: 10
                end
                it "creates a new type on the registry with the same characteristics" do
                    t1 = t0.copy_to(r1)
                    assert_same t1, r1.get(t0.name)
                    assert_equal '/Test', t1.name
                    assert_equal 10, t1.size
                    assert t1.opaque?
                    assert !t1.null?
                end
                it "copies the metadata over" do
                    t0.metadata.set('v0', 'v')
                    t1 = t0.copy_to(r1)
                    assert_equal t1.metadata.to_hash, t0.metadata.to_hash
                end
            end
        end
    end
end

