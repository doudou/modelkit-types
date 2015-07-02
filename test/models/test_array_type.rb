require 'typestore/test'

module TypeStore
    module Models
        describe ArrayType do
            describe "#to_h" do
                attr_reader :array_t, :element_t
                before do
                    @element_t = TypeStore::Type.new_submodel
                    @array_t = TypeStore::ArrayType.new_submodel(deference: element_t, length: 10)
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
                    element_t = TypeStore::Type.new_submodel
                    array_t = TypeStore::ArrayType.new_submodel(deference: element_t, length: 10)
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
        end
    end
end

