require 'modelkit/types/test'

module ModelKit::Types
    module Models
        describe ContainerType do
            it "has a name" do
                assert_equal "ModelKit::Types::ContainerType", ModelKit::Types::ContainerType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::ContainerType.metadata
            end
            describe "#new_submodel" do
                it "sets fixed_buffer_size to false" do
                    element_t = ModelKit::Types::Type.new_submodel
                    container_model = ModelKit::Types::ContainerType.new_submodel(typename: '/std/vector')
                    container_t = container_model.new_submodel(typename: 'container', deference: element_t)
                    assert !container_t.fixed_buffer_size?
                end
            end
            describe "#to_h" do
                attr_reader :container_t, :element_t
                before do
                    @element_t = ModelKit::Types::Type.new_submodel
                    container_model = ModelKit::Types::ContainerType.new_submodel(typename: '/std/vector')

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

