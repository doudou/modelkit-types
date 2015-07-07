require 'typestore/test'

module TypeStore
    module Models
        describe ContainerType do
            describe "#to_h" do
                attr_reader :container_t, :element_t
                before do
                    @element_t = TypeStore::Type.new_submodel
                    container_model = TypeStore::ContainerType.new_submodel(typename: '/std/vector')

                    @container_t = container_model.new_submodel(typename: 'container', deference: element_t)
                end

                it "should be able to describe the type" do
                    expected = Hash[class: 'ContainerType',
                                    kind: container_t.container_model.name,
                                    name: container_t.name,
                                    element: element_t.to_h_minimal(layout_info: false)]
                    assert_equal expected, container_t.to_h(layout_info: false, recursive: false)
                end

                it "should describe the sub-type fully if recursive is true" do
                    expected = Hash[class: 'ContainerType',
                                    kind: container_t.container_model.name,
                                    name: container_t.name,
                                    element: element_t.to_h(layout_info: false)]
                    assert_equal expected, container_t.to_h(layout_info: false, recursive: true)
                end
            end
        end
    end
end

