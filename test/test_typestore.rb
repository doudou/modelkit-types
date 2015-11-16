require 'modelkit/types/test'

describe ModelKit::Types do
    describe ".typename_parts" do
        it "handles simple cases" do
            assert_equal %w{NS2 NS3 Test}, ModelKit::Types.typename_parts("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Scalar},
                ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Gaussian</double,3> Scalar},
                ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal %w{std vector</wrappers/Matrix</double,3,1>>},
                ModelKit::Types.typename_parts("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal %w{NS2 NS3 Test}, ModelKit::Types.typename_parts("/NS2/NS3/Test", '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Scalar},
                    ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Scalar", '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Gaussian<::double,3> Scalar},
                    ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal %w{std vector<::wrappers::Matrix<::double,3,1>>},
                    ModelKit::Types.typename_parts("/std/vector</wrappers/Matrix</double,3,1>>", '::')
            end
        end
    end

    describe ".namespace" do
        it "handles simple cases" do
            assert_equal "/NS2/NS3/", ModelKit::Types.namespace("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal"/wrappers/Matrix</double,3,1>/", ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal "/wrappers/Matrix</double,3,1>/Gaussian</double,3>/",
                ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "/std/", ModelKit::Types.namespace("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        it "returns the separator for root types" do
            assert_equal '/', ModelKit::Types.namespace('/Test')
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal "::NS2::NS3::", ModelKit::Types.namespace("/NS2/NS3/Test", '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal"::wrappers::Matrix<::double,3,1>::",
                    ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Scalar", '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal "::wrappers::Matrix<::double,3,1>::Gaussian<::double,3>::",
                    ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal "::std::", ModelKit::Types.namespace("/std/vector</wrappers/Matrix</double,3,1>>", '::')
            end
        end
    end

    describe ".basename" do
        it "handles simple cases" do
            assert_equal "Test", ModelKit::Types.basename("/NS2/NS3/Test")
        end
        it "handles template patterns as basenames" do
            assert_equal "Scalar", ModelKit::Types.basename("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as basenames" do
            assert_equal "Scalar",
                ModelKit::Types.basename("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "vector</wrappers/Matrix</double,3,1>>",
                ModelKit::Types.basename("/std/vector</wrappers/Matrix</double,3,1>>")
        end
        it "handles recursive templates as type basename with namespace change" do
            assert_equal "vector<::wrappers::Matrix<::double,3,1>>",
                ModelKit::Types.basename("/std/vector</wrappers/Matrix</double,3,1>>", '::')
        end
        it "handles root types" do
            assert_equal 'Test', ModelKit::Types.basename('/Test')
        end
    end

    describe ".validate_typename" do
        it "raises if alphabetic characters are found as array subscripts" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/int[e]") }
        end
        it "raises if negative numbers are found as array subscripts" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/int[-10]") }
        end
        it "raises on known cases" do
            ModelKit::Types.validate_typename "/std/string</double>"
            ModelKit::Types.validate_typename "/std/string</double>"
            ModelKit::Types.validate_typename "/std/string</double,9,/std/string>"
            ModelKit::Types.validate_typename "/std/string<3>"
            ModelKit::Types.validate_typename "/double[3]"
            ModelKit::Types.validate_typename "/std/string</double[3]>"
            ModelKit::Types.validate_typename "/wrappers/Matrix</double,3,1>/Scalar"
            ModelKit::Types.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>"
            ModelKit::Types.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>[4]"
            ModelKit::Types.validate_typename "/std/map</std/string,/trigger/behaviour/Description,/std/less</std/string>,/std/allocator</std/pair</const std/basic_string</char,/std/char_traits</char>,/std/allocator</char>>,/trigger/behaviour/Description>>>"
        end
        it "raises on known cases" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std::string") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std::string") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/std/string<double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std/string<double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std/string</double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("s") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename(":blabla") }
        end
    end

    describe ".parse_template" do
        it "handles typenames without template markers" do
            assert_equal ["base",[]], ModelKit::Types.parse_template("base")
        end
        it "parses a simple template argument" do
            assert_equal ["base",['10']], ModelKit::Types.parse_template("base<10>")
        end
        it "parses multiple template arguments" do
            assert_equal ["base",['10', '20', 'test']], ModelKit::Types.parse_template("base<10,20,test>")
        end
        it "parses recursive template arguments" do
            assert_equal ["base",['10', '20<foo>', 'test<foo,test<bar>>']], ModelKit::Types.parse_template("base<10,20<foo>,test<foo,test<bar>>>")
        end
    end
end

