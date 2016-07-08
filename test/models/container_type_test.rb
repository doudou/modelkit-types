require 'test_helper'

module ModelKit::Types
    module Models
        describe ContainerType do
            it "has a name" do
                assert_equal "ModelKit::Types::ContainerType", ModelKit::Types::ContainerType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::ContainerType.metadata
            end
            it "is not fixed size" do
                refute ModelKit::Types::ContainerType.fixed_buffer_size?
                refute ModelKit::Types::ContainerType.new_submodel.fixed_buffer_size?
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
            describe "#merge" do
                it "raises MismatchingContainerModel if the two containers have a different container model" do
                    r0, r1 = Registry.new, Registry.new
                    element_t = r0.create_type '/Test'
                    container_m = r0.create_container_model '/std/vector'
                    container_t = r0.create_container(container_m, element_t, typename: '/container_test')

                    other_element_t = r1.create_type '/Test'
                    other_container_m = r1.create_container_model '/std/pair'
                    other_container_t = r1.create_container(other_container_m, other_element_t, typename: '/container_test')

                    assert_raises(MismatchingContainerModel) do
                        container_t.registry.merge(other_container_t.registry)
                    end
                end
                it "accepts a merge involving two types with equivalent container models" do
                    r0, r1 = Registry.new, Registry.new
                    element_t = r0.create_type '/Test'
                    container_m = r0.create_container_model '/std/vector'
                    container_t = r0.create_container(container_m, element_t, typename: '/container_test')

                    other_element_t = r1.create_type '/Test'
                    other_container_m = r1.create_container_model '/std/vector'
                    other_container_t = r1.create_container(other_container_m, other_element_t, typename: '/container_test')

                    container_t.registry.merge(other_container_t.registry)
                end
            end

            describe "#copy_to" do
                attr_reader :element_t, :container_t, :container_m
                before do
                    registry = Registry.new
                    @element_t = registry.create_type '/Test'
                    @container_m = registry.create_container_model '/std/vector'
                    @container_t = registry.create_container(container_m, element_t, typename: '/container_test')
                end

                it "can be copied to a different registry" do
                    target_registry = Registry.new
                    target_element_t = target_registry.create_type '/Test'
                    target_container_m = target_registry.create_container_model '/std/vector'
                    target_container_t = container_t.copy_to(target_registry)

                    refute_same  container_t, target_container_t
                    assert_equal container_t, target_container_t
                    assert_same  target_registry.get('/container_test'), target_container_t
                end
                it "registers a missing container model" do
                    target_registry = Registry.new
                    target_element_t = target_registry.create_type '/Test'
                    target_container_t = container_t.copy_to(target_registry)
                    target_container_m = target_container_t.container_model
                    assert_same  container_m, target_container_m
                    assert_same  target_registry.container_model_by_name('/std/vector'), target_container_m
                end
                it "copies its element model" do
                    target_registry = Registry.new
                    target_container_t = container_t.copy_to(target_registry)
                    target_element_t = target_container_t.deference
                    refute_same  element_t, target_element_t
                    assert_equal element_t, target_element_t
                    assert_same  target_registry.get('/Test'), target_element_t
                end
            end
        end
    end
end

