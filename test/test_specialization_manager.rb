require 'typestore/test'

module TypeStore
    describe SpecializationManager do
        subject { SpecializationManager.new }
        let(:registry) { Registry.new(specialization_manager: subject) }
        it "includes modules created by #specialize on matching classes" do
            subject.specialize '/Test' do
                def new_method; end
            end
            type = registry.create_type '/Test'
            assert type.method_defined?(:new_method)
        end
        it "extends the type class with modules created by #specialize_model" do
            subject.specialize_model '/Test' do
                def new_method; end
            end
            type = registry.create_type '/Test'
            assert type.respond_to?(:new_method)
        end
        it "applies the convertions from ruby to the type class" do
            unique_obj = flexmock
            subject.convert_from_ruby(Array, '/Test') { unique_obj }
            type = registry.create_type '/Test'
            assert_equal unique_obj, type.convertions_from_ruby[Array].call
        end
        it "applies the convertion to ruby to the type class" do
            unique_obj = flexmock
            subject.convert_to_ruby('/Test', Array) { unique_obj }
            type = registry.create_type '/Test'

            klass, options = type.convertion_to_ruby
            assert_equal Array, klass
            assert_equal unique_obj, options[:block].call
        end
    end
end



