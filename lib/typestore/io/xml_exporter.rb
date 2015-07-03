require 'typestore'
require 'rexml/document'

module TypeStore
    module IO
        # Marshalling/demarshalling of a {Registry} into TypeStore's own XML
        # format
        class XMLExporter
            def self.export(registry, to: '')
                new.export(registry, to: to)
            end

            def export(registry, to: '')
                xml = to_xml(registry)
                REXML::Formatters::Pretty.new.
                    write(xml, to)
                to
            end

            def self.create_xml
                doc = REXML::Document.new
                doc << REXML::XMLDecl.new
                doc.add_element 'typelib'
            end

            # Convert a registry into a REXML::Document
            def to_xml(registry, root: self.class.create_xml)
                registry.each_type_topological do |type|
                    if type <= ArrayType
                    elsif type <= CompoundType
                        update_compound_node(type, root.add_element('compound'))
                    elsif type <= NumericType
                        update_numeric_node(type, root.add_element('numeric'))
                    elsif type <= EnumType
                        update_enum_node(type, root.add_element('enum'))
                    elsif type <= ContainerType
                        update_container_node(type, root.add_element('container'))
                    else
                        node_name =
                            if type.opaque? then 'opaque'
                            elsif type.null? then 'null'
                            else 'type'
                            end
                        update_type_node(type, root.add_element(node_name))
                    end
                end

                registry.each_alias do |name, type|
                    root.add_element 'alias', 'name' => name, 'source' => type.name
                end
                root.document
            end

            def add_metadata(node, metadata)
                metadata.each do |key, values|
                    values.each do |v|
                        metadata_node = node.add_element 'metadata', 'key' => key.to_s
                        metadata_node.add(REXML::CData.new(v.to_s))
                    end
                end
            end

            def update_type_node(type, node)
                node.attributes['name']   = type.name
                if type.size != 0
                    node.attributes['size']   = type.size
                end
                if type.opaque?
                    node.attributes['opaque'] = '1'
                end
                if type.null?
                    node.attributes['null']   = '1'
                end
                add_metadata(node, type.metadata)
            end

            def update_numeric_node(type, node)
                node.attributes['category'] =
                    if type.integer?
                        if type.unsigned? then 'uint'
                        else 'sint'
                        end
                    else
                        'float'
                    end
                update_type_node(type, node)
            end

            def update_compound_node(type, node)
                type.each do |field|
                    field_node = node.add_element('field',
                        'name' => field.name,
                        'offset' => field.offset,
                        'type' => field.type.name)
                    add_metadata(field_node, field.metadata)
                end
                update_type_node(type, node)
            end

            def update_enum_node(type, node)
                type.each do |sym, v|
                    node.add_element('value',
                         'symbol' => sym.to_s,
                         'value' => v)
                end
                update_type_node(type, node)
            end

            def update_container_node(type, node)
                node.attributes['kind'] = type.container_kind.name
                node.attributes['of']   = type.deference.name
                update_type_node(type, node)
            end
        end
    end
end

