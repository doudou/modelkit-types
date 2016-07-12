require 'test_helper'
module ModelKit::Types
    module IO
        describe CSV do
            attr_reader :int32_t, :double_t, :registry
            before do
                @registry = Registry.new
                @int32_t = registry.create_numeric '/int32', size: 4, integer: true, unsigned: false
                @double_t = registry.create_numeric '/float64', size: 8, integer: false
            end

            it "raises ArgumentError for an unknown type model" do
                assert_raises(ArgumentError) do
                    CSV.export(Object.new)
                end
                assert_raises(ArgumentError) do
                    CSV.export_type(Class.new)
                end
            end

            describe "compound types" do
                attr_reader :simple_t, :recursive_t
                before do
                    @simple_t = registry.create_compound '/Simple' do |c|
                        c.add 'a', int32_t
                        c.add 'b', double_t
                    end
                    field_x_t = registry.create_compound '/FieldA' do |c|
                        c.add 'a', int32_t
                    end
                    field_b_t = registry.create_array int32_t, 3
                    @recursive_t = registry.create_compound '/Recursive' do |c|
                        c.add 'x', field_x_t
                        c.add 'b', field_b_t
                    end
                end

                it "lists a compound's type fields" do
                    assert_equal '.a,.b', CSV.export_type(simple_t)
                end
                it "recursively resolves the compound type field's description" do
                    assert_equal '.x.a,.b[]', CSV.export_type(recursive_t)
                end
                it "lists a compound's fields" do
                    simple = simple_t.from_ruby(a: 10, b: 0.1)
                    assert_equal '10,0.1', CSV.export(simple)
                end
                it "recursively resolves the compound field's description" do
                    recursive = recursive_t.from_ruby(x: Hash[a: 10], b: [1, 2, 3])
                    assert_equal '10,1,2,3', CSV.export(recursive)
                end
            end

            describe "array types" do
                attr_reader :simple_t, :recursive_t
                before do
                    @simple_t = registry.create_array int32_t, 3
                    element_t = registry.create_compound '/Element' do |c|
                        c.add 'a', int32_t
                    end
                    @recursive_t = registry.create_array element_t, 3
                end

                it "lists an array as []" do
                    assert_equal '[]', CSV.export_type(simple_t)
                end
                it "recursively resolves the array's type" do
                    assert_equal '[].a', CSV.export_type(recursive_t)
                end
                it "lists an array's values" do
                    array = simple_t.from_ruby([1, 2, 3])
                    assert_equal '1,2,3', CSV.export(array)
                end
                it "recursively resolves the array's type" do
                    array = recursive_t.from_ruby([Hash[a: 1], Hash[a: 2], Hash[a: 3]])
                    assert_equal '1,2,3', CSV.export(array)
                end
            end

            describe "container types" do
                attr_reader :simple_t, :recursive_t
                before do
                    container_m = registry.create_container_model '/vec'
                    @simple_t = registry.create_container container_m, int32_t
                    element_t = registry.create_compound '/Element' do |c|
                        c.add 'a', int32_t
                    end
                    @recursive_t = registry.create_container container_m, element_t
                end

                it "lists a container as []" do
                    assert_equal '[]', CSV.export_type(simple_t)
                end
                it "recursively resolves the container's type" do
                    assert_equal '[].a', CSV.export_type(recursive_t)
                end
                it "lists a container's elements" do
                    container = simple_t.from_ruby([1, 2, 3, 4])
                    assert_equal '1,2,3,4', CSV.export(container)
                end
                it "recursively resolves the container's elements" do
                    container = recursive_t.from_ruby([Hash[a: 1], Hash[a: 2], Hash[a: 3]])
                    assert_equal '1,2,3', CSV.export(container)
                end
            end
        end
    end
end

