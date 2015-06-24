require 'typestore/test'

describe TypeStore do
    describe ".split_typename" do
        it "handles simple cases" do
            assert_equal %w{NS2 NS3 Test}, TypeStore.split_typename("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Scalar},
                TypeStore.split_typename("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Gaussian</double,3> Scalar},
                TypeStore.split_typename("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal %w{std vector</wrappers/Matrix</double,3,1>>},
                TypeStore.split_typename("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal %w{NS2 NS3 Test}, TypeStore.split_typename("/NS2/NS3/Test", '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Scalar},
                    TypeStore.split_typename("/wrappers/Matrix</double,3,1>/Scalar", '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Gaussian<::double,3> Scalar},
                    TypeStore.split_typename("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal %w{std vector<::wrappers::Matrix<::double,3,1>>},
                    TypeStore.split_typename("/std/vector</wrappers/Matrix</double,3,1>>", '::')
            end
        end
    end

    describe ".namespace" do
        it "handles simple cases" do
            assert_equal "/NS2/NS3/", TypeStore.namespace("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal"/wrappers/Matrix</double,3,1>/", TypeStore.namespace("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal "/wrappers/Matrix</double,3,1>/Gaussian</double,3>/",
                TypeStore.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "/std/", TypeStore.namespace("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal "::NS2::NS3::", TypeStore.namespace("/NS2/NS3/Test", '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal"::wrappers::Matrix<::double,3,1>::",
                    TypeStore.namespace("/wrappers/Matrix</double,3,1>/Scalar", '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal "::wrappers::Matrix<::double,3,1>::Gaussian<::double,3>::",
                    TypeStore.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal "::std::", TypeStore.namespace("/std/vector</wrappers/Matrix</double,3,1>>", '::')
            end
        end
    end

    describe ".basename" do
        it "handles simple cases" do
            assert_equal "Test", TypeStore.basename("/NS2/NS3/Test")
        end
        it "handles template patterns as basenames" do
            assert_equal "Scalar", TypeStore.basename("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as basenames" do
            assert_equal "Scalar",
                TypeStore.basename("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "vector</wrappers/Matrix</double,3,1>>",
                TypeStore.basename("/std/vector</wrappers/Matrix</double,3,1>>")
        end
        it "handles recursive templates as type basename with namespace change" do
            assert_equal "vector<::wrappers::Matrix<::double,3,1>>",
                TypeStore.basename("/std/vector</wrappers/Matrix</double,3,1>>", '::')
        end
    end

    describe ".validate_typename" do
        it "raises if alphabetic characters are found as array subscripts" do
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("/int[e]") }
        end
        it "raises if negative numbers are found as array subscripts" do
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("/int[-10]") }
        end
        it "raises on known cases" do
            TypeStore.validate_typename "/std/string</double>"
            TypeStore.validate_typename "/std/string</double>"
            TypeStore.validate_typename "/std/string</double,9,/std/string>"
            TypeStore.validate_typename "/std/string<3>"
            TypeStore.validate_typename "/double[3]"
            TypeStore.validate_typename "/std/string</double[3]>"
            TypeStore.validate_typename "/wrappers/Matrix</double,3,1>/Scalar"
            TypeStore.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>"
            TypeStore.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>[4]"
            TypeStore.validate_typename "/std/map</std/string,/trigger/behaviour/Description,/std/less</std/string>,/std/allocator</std/pair</const std/basic_string</char,/std/char_traits</char>,/std/allocator</char>>,/trigger/behaviour/Description>>>"
        end
        it "raises on known cases" do
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("std::string") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("std::string") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("/std/string<double>") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("std/string<double>") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("std/string</double>") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename("s") }
            assert_raises(TypeStore::InvalidTypeNameError) { TypeStore.validate_typename(":blabla") }
        end
    end
end

