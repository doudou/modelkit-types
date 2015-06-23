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
                    expected = Hash[class: 'TypeStore::ArrayType',
                                    name: array_t.name,
                                    element: element_t.to_h_minimal(layout_info: false),
                                    length: 10]
                    assert_equal expected, array_t.to_h(layout_info: false, recursive: false)
                end

                it "should describe the sub-type fully if recursive is true" do
                    expected = Hash[class: 'TypeStore::ArrayType',
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
        end
    end
end

