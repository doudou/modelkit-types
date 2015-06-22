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
        end
    end
end

