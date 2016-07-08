require 'test_helper'

module ModelKit::Types
    describe RegistryExport do
        attr_reader :reg, :root
        before do
            @reg = Registry.new
            @root = RegistryExport::Namespace.new
            root.reset_registry_export(reg, nil)
        end

        describe "access from constants" do
            it "gives access to toplevel objects" do
                type = reg.create_compound '/CustomType'
                assert_same type, root::CustomType
            end
            it "raises NameError if the type does not exist" do
                error = assert_raises(RegistryExport::NotFound) { root::DoesNotExist }
                assert((error.message =~ /DoesNotExist/), "expected the NotFound message to include the name of the type (DoesNotExist), but the message was #{error.message}")
            end
            it "handles types mixed case if needed" do
                type = reg.create_compound '/CustomTypeWith_camelCase'
                assert_same type, root::Custom_typeWith_camelCase
            end
            it "handles namespaces mixed case if needed" do
                type = reg.create_compound '/CustomTypeWith_camelCase/Child'
                assert_same type, root::Custom_typeWith_camelCase::Child
            end
            it "gives access to types defined inside other types" do
                parent_type = reg.create_compound '/Parent'
                child_type = reg.create_compound '/Parent/Child'
                assert_same parent_type, root::Parent
                assert_same child_type, root::Parent::Child
            end
            it "gives access to types defined inside namespaces" do
                type = reg.create_compound '/NS/Child'
                assert_same type, root::NS::Child
            end
        end

        describe "access from methods" do
            it "raises TypeNotFound if the type does not exist" do
                assert_raises(RegistryExport::NotFound) { root.DoesNotExist }
            end
            it "gives access to toplevel objects" do
                type = reg.create_compound '/CustomType'
                assert_same type, root.CustomType
            end
            it "gives access to types defined inside other types" do
                parent_type = reg.create_compound '/Parent'
                child_type = reg.create_compound '/Parent/Child'
                assert_same parent_type, root.Parent
                assert_same child_type, root.Parent.Child
            end
            it "gives access to types defined inside namespaces" do
                type = reg.create_compound '/NS/Child'
                assert_same type, root.NS.Child
            end
            it "gives access to template types" do
                parent_type = reg.create_compound '/NS/Template<-1,/TEST>'
                child_type = reg.create_compound '/NS/Template<-1,/TEST>/Child'
                assert_equal parent_type, root.NS.Template(-1,'/TEST')
                assert_equal child_type, root.NS.Template(-1,'/TEST').Child
            end
            it "can use type objects as template access arguments" do
                test_t = reg.create_type '/TEST'
                parent_type = reg.create_compound '/NS/Template<-1,/TEST>'
                child_type = reg.create_compound '/NS/Template<-1,/TEST>/Child'
                assert_equal parent_type, root.NS.Template(-1,test_t)
                assert_equal child_type, root.NS.Template(-1,test_t).Child
            end
            it "gives access to template namespaces using the method syntax" do
                type = reg.create_compound '/NS/Template<-1,/TEST>/Child'
                assert_equal type, root.NS.Template(-1,'/TEST').Child
            end
        end

        describe "the filter block" do
            attr_reader :type
            before do
                @type = reg.create_compound '/CustomType'
            end

            it "gets passed the type" do
                recorder = flexmock
                recorder.should_receive(:call).with(type).once
                root.reset_registry_export(reg, ->(type) { recorder.call(type); type })
                root.CustomType
            end
            it "returns the type as returned by the block" do
                root.reset_registry_export(reg, ->(type) { Hash })
                assert_kind_of Hash, root.CustomType.new
            end
            it "will not export types for which the block returned nil" do
                root.reset_registry_export(reg, ->(type) { })
                assert_raises(RegistryExport::NotFound) do
                    root.CustomType
                end
            end
        end
        
        describe "#disable_registry_export" do
            attr_reader :type
            before do
                @type = reg.create_compound '/CustomType'
            end
            it "removes access to the current registry" do
                assert_same type, root.CustomType
                root.disable_registry_export
                assert_raises(RegistryExport::NotFound) do
                    root.CustomType
                end
            end
        end

        describe "#pretty_print" do
            it "displays the namespace as prefix" do
                string = PP.pp(root, '')
                assert_equal "/*\n", string
            end
        end
    end
end
