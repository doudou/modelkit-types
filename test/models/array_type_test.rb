require 'test_helper'

module ModelKit::Types
    module Models
        describe ArrayType do
            it "has a name" do
                assert_equal "ModelKit::Types::ArrayType", ModelKit::Types::ArrayType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::ArrayType.metadata
            end

            describe "#==" do
                attr_reader :element_t
                before do
                    @element_t = ModelKit::Types::Type.new_submodel
                end
                it "returns true if the two arrays are identical" do
                    a = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10
                    b = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10
                    assert_equal a, b
                end
                it "returns false if the two arrays have different lengths" do
                    a = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10
                    b = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 20
                    refute_equal a, b
                end
                it "delegates the equality tests to Type" do
                    other_t = ModelKit::Types::Type.new_submodel size: 1
                    a = ModelKit::Types::ArrayType.new_submodel deference: other_t, length: 10, size: 1
                    b = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10, size: 1
                    refute_equal a, b
                end
                it "delegates the equality tests to IndirectType" do
                    a = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10, size: 1
                    b = ModelKit::Types::ArrayType.new_submodel deference: element_t, length: 10, size: 2
                    refute_equal a, b
                end
            end

            describe "#to_h" do
                attr_reader :array_t, :element_t
                before do
                    @element_t = ModelKit::Types::Type.new_submodel
                    @array_t = ModelKit::Types::ArrayType.new_submodel(deference: element_t, length: 10)
                end

                it "should be able to describe the type" do
                    expected = Hash[class: 'ArrayType',
                                    name: array_t.name,
                                    element: element_t.to_h_minimal(layout_info: false),
                                    length: 10]
                    assert_equal expected, array_t.to_h(layout_info: false, recursive: false)
                end

                it "should describe the sub-type fully if recursive is true" do
                    expected = Hash[class: 'ArrayType',
                                    name: array_t.name,
                                    element: element_t.to_h(layout_info: false),
                                    length: 10]
                    assert_equal expected, array_t.to_h(layout_info: false, recursive: true)
                end
            end

            describe "#[]" do
                it "returns the deference'd type" do
                    element_t = ModelKit::Types::Type.new_submodel
                    array_t = ModelKit::Types::ArrayType.new_submodel(deference: element_t, length: 10)
                    assert_same element_t, array_t.deference
                end
            end

            describe "#copy_to" do
                it "copies the array length over" do
                    r0, r1 = Registry.new, Registry.new
                    t = r0.create_type '/Element'
                    t0 = r0.create_array t, 10, typename: '/Test'
                    t1 = t0.copy_to(r1)
                    assert_equal 10, t1.length
                end
            end

            describe "#casts_to?" do
                attr_reader :array_t, :array_copy_t, :element_t
                before do
                    r0, r1 = Registry.new, Registry.new
                    @element_t = r0.create_type '/Element'
                    @array_t   = r0.create_array element_t, 10, typename: '/Test'
                    @array_copy_t = array_t.copy_to(r1)
                end

                it "returns true for the same type model" do
                    assert array_copy_t.casts_to?(array_t)
                end
                it "returns true for its element type" do
                    assert array_copy_t.casts_to?(element_t)
                end
            end
        end
    end
end

