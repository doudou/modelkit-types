require 'test_helper'

module ModelKit::Types
    module Models
        describe Type do
            it "has a name" do
                assert_equal "ModelKit::Types::Type", ModelKit::Types::Type.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::Type.metadata
            end

            subject { ModelKit::Types::Type.new_submodel }

            describe "#new_submodel" do
                it "inherits the registry by default" do
                    subject.registry = Registry.new
                    assert_same subject.new_submodel.registry, subject.registry
                end
                it "overrides the parent's registry" do
                    subject.registry = reg = Registry.new
                    registry = Registry.new
                    assert_same registry, subject.new_submodel(registry: registry).registry
                end
                it "sets #name to the provided type name" do
                    assert_equal '/Test', subject.new_submodel(typename: '/Test').name
                end
                it "sets #size to the provided type size" do
                    assert_equal 10, subject.new_submodel(size: 10).size
                end
                it "sets #null? to the provided null option" do
                    assert_equal false, subject.new_submodel(null: false).null?
                    assert_equal true, subject.new_submodel(null: true).null?
                end
                it "sets #opaque? to the provided opaque option" do
                    assert_equal false, subject.new_submodel(opaque: false).opaque?
                    assert_equal true, subject.new_submodel(opaque: true).opaque?
                end
                it "sets #contains_opaques? to true if the type is opaque itself" do
                    assert_equal false, subject.new_submodel(opaque: false).contains_opaques?
                    assert_equal true, subject.new_submodel(opaque: true).contains_opaques?
                end
                it "sets fixed_buffer_size? by default" do
                    assert subject.new_submodel.fixed_buffer_size?
                end
            end
            describe "#registry=" do
                it "sets the type's registry" do
                    subject.registry = reg = Registry.new
                    assert_same reg, subject.registry
                end
                it "can be used only once" do
                    subject.registry = Registry.new
                    assert_raises(ArgumentError) { subject.registry = Registry.new }
                end
            end
            describe "#basename" do
                it "calls ModelKit::Types.basename to extract the type's basename" do
                    flexmock(ModelKit::Types).should_receive(:basename).with("/NS1/Bla/Test", separator: '/').
                        once.pass_thru
                    assert_equal "Test", ModelKit::Types::Type.new_submodel(typename: "/NS1/Bla/Test").basename
                end
            end
            describe "#namespace" do
                it "calls ModelKit::Types.namespace to extract the type's namespace" do
                    flexmock(ModelKit::Types).should_receive(:namespace).with("/NS1/Bla/Test", separator: '/', remove_leading: false).
                        once.pass_thru
                    assert_equal "/NS1/Bla/", ModelKit::Types::Type.new_submodel(typename: "/NS1/Bla/Test").namespace
                end
            end
            describe "#split_typename" do
                it "calls ModelKit::Types.split_typename to split the type's name" do
                    flexmock(ModelKit::Types).should_receive(:split_typename).with("/NS1/Bla/Test", separator: '/').
                        once.pass_thru
                    assert_equal ["/NS1/Bla/", "Test"],
                        ModelKit::Types::Type.new_submodel(typename: "/NS1/Bla/Test").split_typename
                end
            end
            describe "#metadata" do
                it "always returns the same MetaData object" do
                    t = ModelKit::Types::Type.new_submodel
                    assert_same t.metadata, t.metadata
                end
                it "returns a MetaData object" do
                    assert_kind_of MetaData, ModelKit::Types::Type.new_submodel.metadata
                end
                it "returns the type's own MetaData object" do
                    refute_same ModelKit::Types::Type.metadata, ModelKit::Types::Type.new_submodel.metadata
                end
            end
            describe "XML marshalling" do
                it "marshals and unmarshals metadata" do
                    registry = ModelKit::Types::Registry.new
                    t = registry.create_type '/Test'
                    t.metadata.set('k', 'v0', 'v1')
                    t = ModelKit::Types::Registry.from_xml(t.to_xml).get(t.name)
                    assert_equal [['k', ['v0', 'v1'].to_set]], t.metadata.each.to_a
                end
            end
            describe "#merge" do
                it "merges the metadata together" do
                    t0 = ModelKit::Types::Type.new_submodel
                    t1 = ModelKit::Types::Type.new_submodel
                    flexmock(t0.metadata).should_receive(:merge).with(t1.metadata).once
                    t0.merge(t1)
                end
            end
            describe 'dependency management' do
                subject { ModelKit::Types::Type.new_submodel }
                it "returns an empty recursive dependency set" do
                    assert_equal Set.new, subject.recursive_dependencies
                end
                it "adds direct dependencies through #add_direct_dependency" do
                    subject.add_direct_dependency(t = ModelKit::Types::Type.new_submodel)
                    assert_equal Set[t], subject.direct_dependencies
                end
                it "invalidates the cached recursive_dependencies set when a new direct dependency is added" do
                    subject.direct_dependencies
                    subject.add_direct_dependency(t = ModelKit::Types::Type.new_submodel)
                    assert_equal Set[t], subject.direct_dependencies
                end
                it "recursively discovers dependencies in #recursive_dependencies" do
                    t0, t1, *types = (0..7).map { ModelKit::Types::Type.new_submodel }
                    t0.add_direct_dependency types[0]
                    t0.add_direct_dependency types[1]
                    t0.add_direct_dependency types[2]
                    t1.add_direct_dependency types[3]
                    t1.add_direct_dependency types[4]
                    t1.add_direct_dependency types[5]
                    subject.add_direct_dependency t0
                    subject.add_direct_dependency t1
                    assert_equal Set[t0, t1, *types], subject.recursive_dependencies
                end
                it "discovers the dependencies of a given type only once" do
                    t0, t1, t2 = (0..2).map { ModelKit::Types::Type.new_submodel }
                    t0.add_direct_dependency t2
                    t1.add_direct_dependency t2
                    subject.add_direct_dependency t0
                    subject.add_direct_dependency t1
                    flexmock(t2).should_receive(:direct_dependencies).once.and_return(Set.new)
                    subject.recursive_dependencies
                end
                it "caches the result" do
                    assert_same subject.recursive_dependencies, subject.recursive_dependencies
                end
            end
            describe "#validate_merge" do
                it "passes for equivalent types" do
                    t0 = ModelKit::Types::Type.new_submodel(typename: 't', size: 10, opaque: false, null: true)
                    t1 = ModelKit::Types::Type.new_submodel(typename: 't', size: 10, opaque: false, null: true)
                    t0.validate_merge(t1)
                end
                it "raises InvalidMerge if the names differ" do
                    t0 = ModelKit::Types::Type.new_submodel typename: 't0'
                    t1 = ModelKit::Types::Type.new_submodel typename: 't1'
                    assert_raises(MismatchingTypeNameError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the supermodels differ" do
                    t0 = ModelKit::Types::CompoundType.new_submodel
                    t1 = ModelKit::Types::Type.new_submodel
                    assert_raises(MismatchingTypeModelError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the sizes differ" do
                    t0 = ModelKit::Types::Type.new_submodel size: 1
                    t1 = ModelKit::Types::Type.new_submodel size: 2
                    assert_raises(MismatchingTypeSizeError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the opaque flag differ" do
                    t0 = ModelKit::Types::Type.new_submodel opaque: true
                    t1 = ModelKit::Types::Type.new_submodel opaque: false
                    assert_raises(MismatchingTypeOpaqueFlagError) { t0.validate_merge(t1) }
                end
                it "raises InvalidMerge if the null flag differ" do
                    t0 = ModelKit::Types::Type.new_submodel null: true
                    t1 = ModelKit::Types::Type.new_submodel null: false
                    assert_raises(MismatchingTypeNullFlagError) { t0.validate_merge(t1) }
                end
            end

            describe "#copy_to" do
                attr_reader :r0, :r1, :t0
                before do
                    @r0, @r1 = Registry.new, Registry.new
                    @t0 = r0.create_type '/Test', opaque: true, null: false, size: 10
                end
                it "creates a new type on the registry with the same characteristics" do
                    t1 = t0.copy_to(r1)
                    assert_same t1, r1.get(t0.name)
                    assert_equal '/Test', t1.name
                    assert_equal 10, t1.size
                    assert t1.opaque?
                    assert !t1.null?
                end
                it "copies the metadata over" do
                    t0.metadata.set('v0', 'v')
                    t1 = t0.copy_to(r1)
                    assert_equal t1.metadata.to_hash, t0.metadata.to_hash
                end
            end

            describe "#pretty_print" do
                attr_reader :type
                before do
                    registry = Registry.new
                    @type = registry.create_type '/Test', opaque: true, null: false, size: 10
                    type.metadata.set('doc', "a multiline\ndoc")
                end
                it "does not raise" do
                    pp = PP.new('')
                    type.pretty_print(pp, with_doc: true, verbose: true)
                end
            end

            describe "#contains?" do
                attr_reader :type
                before do
                    registry = Registry.new
                    @type = registry.create_type '/Test', opaque: true, null: false, size: 10
                end

                it "returns true for self" do
                    assert type.contains?(type)
                end
                it "returns true for a supermodel of self" do
                    assert type.contains?(type.supermodel)
                end
                it "returns true for a recursive dependency of self" do
                    flexmock(type).should_receive(:recursive_dependencies).and_return([klass = Class.new])
                    assert type.contains?(klass)
                end
                it "returns true for a supermodel of a recursive dependency of self" do
                    dependency = ModelKit::Types::Type.new_submodel
                    sub = Class.new(dependency)
                    flexmock(type).should_receive(:recursive_dependencies).and_return([sub])
                    assert type.contains?(dependency)
                end
            end

            describe "#buffer_size_at" do
                it "returns the type's size if it is fixed-size" do
                    type = ModelKit::Types::Type.new_submodel(size: 20)
                    assert_equal 20, type.buffer_size_at("", 0)
                end
                it "raises NotImplementedError if it is variable-size" do
                    type = ModelKit::Types::Type.new_submodel(size: 20)
                    type.fixed_buffer_size = false
                    assert_raises(NotImplementedError) do
                        type.buffer_size_at("", 0)
                    end
                end
            end
        end
    end
end

