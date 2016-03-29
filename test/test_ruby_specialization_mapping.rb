require 'modelkit/types/test'

module ModelKit::Types
    describe RubySpecializationMapping do
        subject { RubySpecializationMapping.new }
        let(:type) { Type.new_submodel typename: '/Test' }
        it "resolves full type names" do
            subject.add '/Test', 10
            subject.add '/Foo', 20
            assert_equal [10], subject.find_all(type)
        end
        it "resolves using regular expressions" do
            subject.add(/T/, 10)
            subject.add(/E/, 20)
            assert_equal [10], subject.find_all(type)
        end
        it "resolves using its name argument" do
            subject.add '/Foo', 10
            assert_equal [10], subject.find_all(type, name: '/Foo')
        end
        it "resolves arrays-of-T" do
            array_t = ArrayType.new_submodel deference: type
            subject.add '/Test[]', 10
            assert_equal [10], subject.find_all(array_t)
            assert_equal [], subject.find_all(type)
        end
        it "resolves containers" do
            container_model = ContainerType.new_submodel typename: '/std/vector'
            container_t = container_model.new_submodel(
                typename: '/std/vector</Test>', deference: type)
            subject.add '/std/vector<>', 10
            assert_equal [10], subject.find_all(container_t)
            assert_equal [], subject.find_all(type)
        end

        it "does not return entries for which the if: argument returns false" do
            conditional = flexmock
            conditional.should_receive(:call).with(type).and_return(false).once
            subject.add '/Test', 10, if: conditional
            assert_equal [], subject.find_all(type)
        end
    end
end
