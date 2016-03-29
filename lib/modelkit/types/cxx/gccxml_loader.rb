require 'set'
require 'tempfile'
require 'shellwords'

module ModelKit::Types
    module CXX
        # Intermediate representation of a parsed GCCXML output, containing only
        # the information we need (and not the full XML representation)
        class GCCXMLInfo
            # During parsing, the last node that has been discovered
            attr_reader :current_node
            # @return [{String=>String}] the set of files that have been directly
            #   required, as a mapping from the full file path to the GCCXML ID that
            #   represents this file. The IDs are only filled after #parse is called
            attr_reader :required_files
            # @return [{String=>Node}] a mapping from a type ID to the XML node that
            #   stores its definition
            attr_reader :id_to_node
            # @return [{String=>Array<Node>}] a mapping from a mangled type name to the XML
            #   nodes that store its definition
            attr_reader :name_to_nodes
            # @return [{String=>String}] a mapping from all
            #   virtual methods/destructors/operators that have been found. It is
            #   used during resolution to reject the compounds that use them
            attr_reader :virtual_members
            # A mapping from a type ID to the XML node information about its base
            # classes
            attr_reader :bases
            # A mapping from an enum type ID to the XML node information about the
            # values that define it
            attr_reader :enum_values
            # @return [{String=>Array<Node>}] mapping from a file ID to the set of
            #   type-definition nodes that are defined within this file
            attr_reader :types_per_file
            # @return [{String=>Array<Node>}] mapping from a file ID to the set of
            #   typdef-definition nodes that are defined within this file
            attr_reader :typedefs_per_file

            Node = Struct.new :name, :attributes do
                def [](name)
                    attributes[name]
                end
            end

            STORED_TAGS = %w{Namespace Typedef Enumeration Struct Class ArrayType FundamentalType PointerType CvQualifiedType}

            def initialize(required_files)
                @required_files = Hash.new
                required_files.each do |full_path|
                    @required_files[full_path] = nil
                end
                @id_to_node = Hash.new
                @name_to_nodes = Hash.new
                @virtual_members = Set.new

                @bases = Hash.new { |h, k| h[k] = Array.new }
                @enum_values = Hash.new { |h, k| h[k] = Array.new }

                @types_per_file = Hash.new { |h, k| h[k] = Array.new }
                @typedefs_per_file = Hash.new { |h, k| h[k] = Array.new }
            end

            def file(attributes)
                file_name = attributes['name']
                if required_files.has_key?(file_name)
                    required_files[file_name] = attributes['id']
                end
            end

            def tag_start(name, attributes)
                if name == "File"
                    id_to_node[attributes['id']] = Node.new(name, attributes)
                    return file(attributes)
                elsif name == "Field" || name == "FundamentalType"
                    id_to_node[attributes['id']] = Node.new(name, attributes)
                elsif name == "Base"
                    bases[current_node['id']] << Node.new(name, attributes)
                elsif name == "EnumValue"
                    enum_values[current_node['id']] << Node.new(name, attributes)
                elsif attributes['virtual'] == '1'
                    virtual_members << attributes['id']
                end

                return if !STORED_TAGS.include?(name)

                child_node = Node.new(name, attributes)
                id_to_node[child_node['id']] = child_node
                @current_node = child_node
                if (child_node_name = child_node['name'])
                    node_name = GCCXMLLoader.cxx_to_typelib(child_node_name)
                    (name_to_nodes[node_name] ||= Array.new) << child_node
                end

                if name == "Typedef"
                    typedefs_per_file[attributes['file']] << child_node
                elsif %w{Struct Class Enumeration}.include?(name)
                    types_per_file[attributes['file']] << child_node
                end
            end

            def parse(xml)
                lines = xml.split("\n")
                lines.shift
                root_tag = lines.shift
                if root_tag !~ /<GCC_XML/
                    raise RuntimeError, "the provided XML input does not look like a GCCXML output (expected a root GCC_XML tag but got #{root_tag.chomp})"
                end

                lines.each do |l|
                    if match = /<(\w+)/.match(l)
                        name = match[1]
                        parsing_needed = %w{File Field Base EnumValue}.include?(name) ||
                            STORED_TAGS.include?(name)

                        if !parsing_needed
                            if l =~ /virtual="1"/
                                l =~ /id="([^"]+)"/
                                tag_start(name, Hash['id' => $1, 'virtual' => '1'])
                            end
                        else
                            raw_attributes = l.gsub(/&lt;/, "<").gsub(/&gt;/, ">").scan(/\w+="[^"]+"/)
                            attributes = Hash.new
                            raw_attributes.each do |attr|
                                attr_name, attr_value = attr.split("=")
                                attributes[attr_name] = attr_value[1..-2]
                            end
                            tag_start(name, attributes)
                        end
                    end
                end
            end
        end

        # A converted from the output of GCC-XML into a {Registry}
        class GCCXMLLoader
            # @return [GCCXMLInfo] The raw information contained in the GCCXML output
            attr_reader :info
            # The set of types that should be considered as opaques by the engine
            attr_accessor :opaques

            # A mapping from the type ID to the parts that form its full type name
            attr_reader :id_to_name_parts

            # A mapping from the type ID to the corresponding typelib type name
            #
            # If the type name is nil, it means that the type should not be
            # represented in typelib
            attr_reader :id_to_name

            # @return [{String=>String}] mapping from a type ID to the message
            #   explaining why it cannot be represented (it is "ignored")
            # @see {ignore}
            attr_reader :ignore_message

            # The registry that is being filled by parsing GCCXML output
            attr_reader :registry

            # Cached file contents (used to parse documentation)
            attr_reader :source_file_contents

            # A list of aliases that are created during import to help the import,
            # but should not end up in the final registry
            attr_reader :permanent_aliases

            def node_from_id(id)
                info.id_to_node[id]
            end

            def initialize
                @opaques      = Set.new
                @id_to_name_parts   = Hash.new
                @id_to_name   = Hash.new
                @ignore_message = Hash.new
                @source_file_contents = Hash.new
                @permanent_aliases = Set.new
                @registry = Registry.new
            end

            def normalize_type_name(name, resolve: false)
                if resolve && (node = find_node_by_name(name)) && node.name != 'Namespace'
                    return resolve_type_definition(node)
                end

                namespace, basename = ModelKit::Types.split_typename(name)
                if (namespace != '/') && (namespace = normalize_type_name(namespace[0..-2], resolve: true))
                    name = "#{namespace}/#{basename}"
                end

                type_name, template_args = ModelKit::Types.parse_template(name, full_name: true)
                normalized_args = template_args.map do |arg|
                    if arg =~ /^[-=\d]/
                        arg
                    else
                        normalize_type_name(arg, resolve: true)
                    end
                end

                if resolve && (node = find_node_by_name(type_name)) && node.name != 'Namespace'
                    normalized_base_name = resolve_type_definition(node)
                elsif type_name =~ /^(.*)((?:\[\d+\])+)$/
                    element_name, suffix = $1.strip, $2
                    normalized_base_name = "#{normalize_type_name(element_name, resolve: true)}#{suffix}"
                end

                if normalized_args.empty?
                    normalized_base_name || type_name
                else
                    "#{normalized_base_name || type_name}<#{normalized_args.join(",")}>"
                end
            end

            def self.cxx_to_typelib(name)
                name = name.gsub('::', '/')
                name = name.gsub('> >', '>>')

                tokens = ModelKit::Types.typename_tokenizer(name)
                tokenized_cxx_to_typelib(tokens)
            end

            def self.tokenized_cxx_to_typelib(tokens, &filter)
                result = []
                while !tokens.empty?
                    tk = tokens.shift
                    if tk == "<"
                        tokens.unshift(tk)
                        template_arguments = CXX.collect_template_arguments(tokens)
                        args = template_arguments.map do |tk|
                            typelib_name = tokenized_cxx_to_typelib(tk)
                            if filter then filter[typelib_name]
                            else typelib_name
                            end
                        end
                        result[-1] = "#{result[-1]}<#{args.join(",")}>"
                    else
                        result << tk
                    end
                end
                if result[0] != "/" && result[0] !~ /^[-+\d]/
                    result.unshift '/'
                end
                result = result.join("")
                result
            end

            def self.split_first_namespace(typename)
                basename  = typename[1..-1]
                namespace = "/"
                level = 0
                while true
                    next_marker = (basename =~ /[\/<>]/)
                    break if !next_marker

                    namespace << basename[0, next_marker + 1]
                    basename  = basename[(next_marker + 1)..-1]

                    found_char = namespace[-1, 1]
                    if found_char == '/'
                        break if level == 0
                    elsif found_char == '<'
                        level += 1
                    elsif found_char == '>'
                        level -= 1
                    end
                end

                if basename.empty?
                    return ['/', namespace[1..-1]]
                else
                    return namespace, basename
                end
            end

            def self.split_last_namespace(name)
                basename = ""
                typename = name.reverse
                level = 0
                while true
                    next_marker = (typename =~ /[\/<>]/)
                    if !next_marker
                        basename << typename
                        typename = ""
                        break
                    end

                    basename << typename[0, next_marker]
                    typename = typename[next_marker..-1]

                    found_char = typename[0, 1]
                    if found_char == '/'
                        break if level == 0
                    elsif found_char == '<'
                        level += 1
                    elsif found_char == '>'
                        level -= 1
                    end

                    basename << found_char
                    typename = typename[1..-1]
                end

                return typename.reverse, basename.reverse
            end

            NAMESPACE_NODE_TYPES = %w{Namespace Struct Class}

            # Given a full ModelKit::Types type name, returns a [name, id] pair where +name+
            # is the type's basename and +id+ the context ID (i.e. the GCCXML
            # namespace ID)
            def resolve_namespace_of(name)
                context = nil
                while true
                    ns, name = GCCXMLLoader.split_first_namespace(name)
                    name = "/#{name}"
                    break if ns == '/'
                    ns   = ns[0..-2]
                    candidates = (info.name_to_nodes[ns] || Array.new).
                        find_all { |n| NAMESPACE_NODE_TYPES.include?(n.name) }
                    if !context
                        context = candidates.to_a.first
                    else
                        context = candidates.find { |node| node['context'].to_s == context }
                    end
                    if !context
                        break
                    else context = context["id"].to_s
                    end
                end
                return name, context
            end

            def resolve_node_name_parts(id_or_node, cxx: false)
                node = if id_or_node.respond_to?(:to_str)
                           info.id_to_node[id_or_node]
                       else
                           id_or_node
                       end

                if !node['name']
                    return
                else
                    name = node['name']
                    name = name.gsub(/0x0+/, '').
                        gsub(/\s\+\[/, '[')
                    if !cxx
                        # Convert to typelib conventions, and remove the leading
                        # slash
                        name = GCCXMLLoader.cxx_to_typelib(name)[1..-1]
                    elsif name == '::'
                        return ['']
                    end
                    if !node['context'] # root namespace
                        return [name]
                    elsif parent = resolve_node_name_parts(node['context'], cxx: cxx)
                        return parent + [name]
                    end
                end

            end

            def resolve_node_cxx_name(id_or_node)
                if parts = resolve_node_name_parts(id_or_node, cxx: true)
                    parts.map do |n|
                        n.gsub(/,\s*/, ', ').
                            gsub(/<::/, "< ::").
                            gsub(/>>/, "> >")
                    end.join("::")
                end
            end

            def resolve_node_typelib_name(id_or_node)
                if parts = resolve_node_name_parts(id_or_node, cxx: false)
                    result = parts.join("/")
                    if !result.start_with?('/')
                        "/#{result}"
                    else result
                    end
                end
            end

            def resolve_type_id(id)
                id = id.to_str
                if ignored?(id.to_str)
                    nil
                elsif name = id_to_name[id]
                    name
                elsif node = node_from_id(id)
                    resolve_type_definition(node)
                end
            end

            def warn(msg)
                ModelKit::Types.warn msg
            end

            def file_context(xmlnode)
                if (file = xmlnode["file"]) && (line = xmlnode["line"])
                    "#{info.id_to_node[file]["name"]}:#{line}"
                end
            end

            def ignored?(id)
                ignore_message.has_key?(id.to_str)
            end

            def ignore(xmlnode, msg = nil)
                if msg
                    if file = file_context(xmlnode)
                        warn("#{file}: #{msg}")
                    else
                        warn(msg)
                    end
                end
                ignore_message[xmlnode['id']] = msg
                nil
            end

            # Returns if +name+ has been declared as an opaque
            def opaque?(name)
                opaques.include?(name)
            end

            def resolve_qualified_type(xmlnode)
                spec = []
                if xmlnode['const'] == '1'
                    spec << 'const'
                end
                if xmlnode['volatile'] == "1"
                    spec << 'volatile'
                end
                if name = resolve_type_id(xmlnode['type'])
                    return "#{name} #{spec.join(" ")}", registry.get(name)
                end
            end

            def source_file_for(xmlnode)
                if file = info.id_to_node[xmlnode['file']]
                    File.realpath(file['name'])
                end
            rescue Errno::ENOENT
                File.expand_path(file)
            end

            def source_file_content(file)
                if source_file_contents.has_key?(file)
                    source_file_contents[file]
                else
                    if File.file?(file)
                        source_file_contents[file] = File.readlines(file, :encoding => 'utf-8')
                    else
                        source_file_contents[file] = nil
                    end
                end
            end

            def set_source_file(type, xmlnode)
                file = source_file_for(xmlnode)
                return if !file

                if (line = xmlnode["line"]) && (content = source_file_content(file))
                    line = Integer(line)
                    # GCCXML reports the file/line of the opening bracket for
                    # struct/class/enum. We prefer the line of the
                    # struct/class/enum definition.
                    #
                    # Moreover, gccxml's line numbering is 1-based (as it is the
                    # common one for editors)
                    while line >= 0 && content[line - 1] =~ /^\s*{?\s*$/
                        line = line - 1
                    end
                end

                if line
                    type.metadata.add('source_file_line', "#{file}:#{line}")
                else
                    type.metadata.add('source_file_line', file)
                end
            end
            
            def resolve_container_definition(xmlnode, typelib_name, type_name, template_args)
                # This is known as a container
                contained_type = template_args[0]
                if !registry.include?(contained_type)
                    contained_node = find_node_by_name(contained_type)
                    if !contained_node
                        contained_node = find_node_by_name(contained_type)
                        raise "Internal error: cannot find definition for #{contained_type}, element of #{typelib_name}"
                    end
                    if ignored?(contained_node["id"])
                        return ignore(xmlnode, "ignoring #{typelib_name} as its element type #{contained_type} is ignored as well")
                    elsif !resolve_type_definition(contained_node)
                        return ignore(xmlnode, "ignoring #{typelib_name} as its element type #{contained_type} is ignored as well")
                    end
                end
                registry.create_container type_name, template_args[0], size: (Integer(xmlnode['size']) / 8)
            end
            
            def resolve_compound_definition(xmlnode, typelib_name, type_name, template_args)
                if xmlnode['incomplete'] == '1'
                    return ignore(xmlnode, "ignoring incomplete type #{typelib_name}")
                end

                member_ids = (xmlnode['members'] || '').split(" ")
                member_ids.each do |id|
                    if info.virtual_members.include?(id)
                        return ignore(xmlnode, "ignoring #{typelib_name}, it has virtual methods")
                    end
                end

                # Make sure that we can digest it. Forbidden are: non-public members
                base_classes = info.bases[xmlnode['id']].map do |child_node|
                    if child_node['virtual'] != '0'
                        return ignore(xmlnode, "ignoring #{typelib_name}, it has virtual base classes")
                    elsif child_node['access'] != 'public'
                        return ignore(xmlnode, "ignoring #{typelib_name}, it has private base classes")
                    end
                    if base_type_name = resolve_type_id(child_node['type'])
                        base_type = registry.get(base_type_name)
                        [base_type, Integer(child_node['offset'] || '0')]
                    else
                        return ignore(xmlnode, "ignoring #{typelib_name}, it has ignored base classes")
                    end
                end

                fields = member_ids.map do |member_id|
                    if field_node = info.id_to_node[member_id]
                        if field_node.name == "Field"
                            field_node
                        end
                    end
                end.compact

                if fields.empty? && base_classes.all? { |type, _| type.empty? }
                    return ignore(xmlnode, "ignoring the empty struct/class #{typelib_name}")
                end

                normalized_name = normalize_type_name(typelib_name)
                # If we have a recursive construct, where a nested type is used
                # as a field for the parent type, normalize_type_name will
                # resolve both the parent and the nested type.
                #
                # We need to register the id-to-name mapping here before
                # resolving the fields so that we don't get an infinite
                # recursion, and we must check whether the type we're trying to
                # define has not been defined already because of the recursion.
                if registry.include?(normalized_name)
                    return registry.get(normalized_name)
                end
                id_to_name[xmlnode['id']] = normalized_name

                field_defs = fields.map do |field|
                    if field['access'] != 'public'
                        return ignore(xmlnode, "ignoring #{typelib_name} since its field #{field['name']} is private")
                    elsif field_type_name = resolve_type_id(field['type'])
                        [field['name'], field_type_name, Integer(field['offset']) / 8, field['line']]
                    else
                        ignored_type_name = id_to_name[field['type']]
                        if ignored_type_name
                            return ignore(xmlnode, "ignoring #{typelib_name} since its field #{field['name']} is of the ignored type #{ignored_type_name}")
                        else
                            return ignore(xmlnode, "ignoring #{typelib_name} since its field #{field['name']} is of an anonymous type")
                        end
                    end
                end

                # See comment above
                id_to_name.delete(xmlnode['id'])

                type = registry.create_compound(normalized_name, Integer(xmlnode['size']) / 8) do |c|
                    base_classes.each do |base_type, base_offset|
                        base_type.each_field do |name, type|
                            offset = base_type.offset_of(name)
                            c.add(name, type, offset: base_offset + offset)
                        end
                    end

                    field_defs.each do |field_name, field_type, field_offset, field_line|
                        c.add(field_name, field_type, offset: field_offset)
                    end
                end
                base_classes.each do |base_type, _|
                    type.metadata.add('base_classes', base_type.name)
                    base_type.each_field do |name, _|
                        base_type.get(name).metadata.get('source_file_line').each do |file_line|
                            type.get(name).metadata.add('source_file_line', file_line)
                        end
                    end
                end
                if file = source_file_for(xmlnode)
                    field_defs.each do |field_name, _, _, field_line|
                        type.get(field_name).metadata.set('source_file_line', "#{file}:#{field_line}")
                    end
                end
                type
            end
            
            def resolve_fundamental_definition(xmlnode, typelib_name)
                # See to alias it to the modelkit normalized name
                if typelib_name =~ /int|short|char/
                    basename =
                        if typelib_name =~ /unsigned/ then "/uint"
                        else "/int"
                        end
                    registry.get("#{basename}#{xmlnode['size']}")
                elsif typelib_name =~ /float|double/
                    registry.get("/float#{xmlnode['size']}")
                else
                    return ignore(xmlnode, "unknown fundamental type #{typelib_name}")
                end
            end

            def resolve_typedef_definition(xmlnode, typelib_name)
                if !(pointed_to_type = resolve_type_id(xmlnode['type']))
                    return ignore(xmlnode, "cannot create the #{typelib_name} typedef, as it points to #{id_to_name[xmlnode['type']]} which is ignored")
                end
                registry.get(pointed_to_type)
            end

            def resolve_array_definition(xmlnode)
                # Find the pointed-to-type that has a typelib name
                element_xmlnode = xmlnode
                suffixes = []
                while !element_xmlnode['name']
                    suffixes.unshift(element_xmlnode['max'].gsub(/u$/, ''))
                    element_xmlnode = node_from_id(element_xmlnode['type'])
                end
                typelib_name = "#{resolve_node_typelib_name(element_xmlnode)}[#{suffixes.map(&:to_s).join("][")}]"

                if !(pointed_to_type = resolve_type_id(xmlnode['type']))
                    return ignore(xmlnode)
                end

                value = xmlnode["max"]
                if value =~ /^(\d+)u?$/
                    size = Integer($1) + 1
                else
                    raise "expected NUMBER (for castxml) or NUMBERu (for gccxml) for the 'max' attribute of an array definition, but got \'#{value}\'"
                end
                array_type = registry.create_array(pointed_to_type, size)
                array_type.metadata.set('cxxname', "#{array_type.deference.metadata.get('cxxname')}[#{size}]")
                return typelib_name, array_type
            end

            def resolve_enum_definition(xmlnode, typelib_name)
                normalized_name = normalize_type_name(typelib_name)
                registry.create_enum(normalized_name) do |e|
                    info.enum_values[xmlnode['id']].each do |enum_value|
                        e.add(enum_value["name"], Integer(enum_value['init']))
                    end
                end
            end

            def resolve_type_definition(xmlnode)
                kind = xmlnode.name
                id   = xmlnode['id']

                if typelib_name = id_to_name[id]
                    return typelib_name
                end

                access_specifier = xmlnode['access']
                if access_specifier && (access_specifier != 'public')
                    return ignore(xmlnode, "ignoring #{typelib_name} as it has a non-public access specifier: #{access_specifier}")
                end

                typelib_name = resolve_node_typelib_name(xmlnode)

                if kind == "PointerType"
                    return ignore(xmlnode, "pointer types are not supported")
                elsif kind == "ArrayType"
                    typelib_name, resolved_type = resolve_array_definition(xmlnode)
                elsif kind == "CvQualifiedType"
                    typelib_name, resolved_type = resolve_qualified_type(xmlnode)
                elsif !typelib_name || (typelib_name =~ /gccxml_workaround/)
                    return
                elsif registry.include?(typelib_name)
                    resolved_type = registry.get(typelib_name)
                    if resolved_type.metadata.get('opaque_is_typedef').include?('1')
                        return resolved_type.name
                    end
                elsif kind != "Typedef" && typelib_name =~ /\/__\w+$/
                    # This is defined as private STL/Compiler implementation
                    # structures. Just ignore it
                    return ignore(xmlnode)
                elsif kind == "Typedef"
                    resolved_type   = resolve_typedef_definition(xmlnode, typelib_name)
                    normalized_name = normalize_type_name(typelib_name)
                    if !ModelKit::Types.basename(normalized_name).start_with?("__")
                        register_permanent_alias(normalized_name)
                    end
                else
                    if kind == "Struct" || kind == "Class"
                        type_name, template_args = ModelKit::Types.parse_template(typelib_name, full_name: true)
                        if registry.has_container_model?(type_name)
                            resolved_type = resolve_container_definition(xmlnode, typelib_name, type_name, template_args)
                        else
                            resolved_type = resolve_compound_definition(xmlnode, typelib_name, type_name, template_args)
                        end
                    elsif kind == "FundamentalType"
                        if !registry.include?(typelib_name)
                            resolved_type = resolve_fundamental_definition(xmlnode, typelib_name)
                        end

                    elsif kind == "Enumeration"
                        resolved_type = resolve_enum_definition(xmlnode, typelib_name)
                    else
                        return ignore(xmlnode, "ignoring #{typelib_name} as it is of the unsupported GCCXML type #{kind}, XML node is #{xmlnode}")
                    end
                end

                if !resolved_type
                    return
                elsif normalized_name = id_to_name[xmlnode['id']]
                    return normalized_name
                end
                
                if !normalized_name
                    normalized_name = resolved_type.name
                end
                if kind != "Typedef"
                    set_source_file(resolved_type, xmlnode)
                    cxxname ||= resolve_node_cxx_name(xmlnode)
                    if cxxname
                        resolved_type.metadata.set 'cxxname', cxxname
                    end
                    if align = xmlnode['align']
                        resolved_type.metadata.set 'cxx:align', align
                    end
                end
                if typelib_name != resolved_type.name
                    registry.create_alias typelib_name, resolved_type
                end
                if (normalized_name != typelib_name) && (normalized_name != resolved_type.name)
                    registry.create_alias normalized_name, resolved_type
                end
                id_to_name[id] = normalized_name
            end

            def find_node_by_name(typename, node_type: nil)
                if nodes = info.name_to_nodes[typename]
                    return nodes.first
                else
                    basename, context = resolve_namespace_of(typename)
                    return if !context
                    if nodes = info.name_to_nodes[basename]
                        nodes.find do |node|
                            (node['context'].to_s == context) &&
                                (!node_type || (node.name == node_type))
                        end
                    end
                end
            end

            def resolve_std_string
                [['/std/string', '/char'], ['/std/wstring', '/wchar_t']].each do |string_t_name, char_t_name|
                    if node = find_node_by_name(string_t_name, node_type: 'Typedef')
                        type_node = node_from_id(node["type"].to_s)
                        full_name = resolve_node_typelib_name(type_node)
                        string_t = registry.create_container BasicString,
                            registry.get(char_t_name),
                            size: (Integer(type_node['size']) / 8),
                            typename: string_t_name
                        registry.create_alias full_name, string_t

                        # We also need to workaround a problem in castxml, where
                        # vectors of string only refer to the first parameter
                        # of the string template.
                        registry.create_alias "/std/basic_string<#{char_t_name}>", string_t

                        registry.get(string_t_name).metadata.
                            set('cxxname', string_t_name.gsub('/', '::'))
                        id_to_name[node['id']] = string_t.name
                    end
                end
            end

            # This method looks for the real name of opaques
            #
            # The issue with opaques is that they might be either typedefs or
            # templates with default arguments. In both cases, we need to find out
            # their real name 
            #
            # For the typedefs, it it easy
            def resolve_opaques
                # First do typedefs. Search for the typedefs that are named like our
                # type, if we find one, alias it
                opaques.dup.each do |opaque_name|
                    if opaque_node = find_node_by_name(opaque_name, node_type: 'Typedef')
                        type_node = node_from_id(opaque_node["type"].to_s)
                        type_typelib_name = resolve_node_typelib_name(type_node)
                        type_normalized_name = normalize_type_name(type_typelib_name)
                        opaque_t     = registry.get(opaque_name)
                        normalized_name = opaque_t.name

                        opaques << type_typelib_name << type_normalized_name
                        set_source_file(opaque_t, opaque_node)
                        opaque_t.metadata.set('opaque_is_typedef', '1')
                        if cxxname = resolve_node_cxx_name(opaque_node)
                            opaque_t.metadata.set('cxxname', cxxname)
                        end
                        id_to_name[opaque_node['id']] = normalized_name

                        registry.create_alias type_normalized_name, normalized_name
                        if type_typelib_name != type_normalized_name
                            registry.create_alias type_typelib_name, normalized_name
                        end
                    end
                end
            end

            def self.parse_cxx_documentation_before(lines, line)
                lines ||= Array.new

                block = []
                # Lines are given 1-based (as all editors work that way), and we
                # want the line before the definition. Remove two
                line = line - 2
                while true
                    case l = lines[line]
                    when /^\s*$/
                    when /^\s*(\*|\/\/|\/\*)/
                        block << l
                    else break
                    end
                    line = line - 1
                end
                block = block.map do |l|
                    l.strip.gsub(/^\s*(\*+\/?|\/+\**)/, '')
                end
                while block.first && block.first.strip == ""
                    block.shift
                end
                while block.last && block.last.strip == ""
                    block.pop
                end
                # Now remove the same amount of spaces in front of each lines
                space_count = block.map do |l|
                    l =~ /^(\s*)/
                    if $1.size != l.size
                        $1.size
                    end
                end.compact.min
                block = block.map do |l|
                    l[space_count..-1]
                end
                if last_line = block[0]
                    last_line.gsub!(/\*+\//, '')
                end
                if !block.empty?
                    block.reverse.join("\n")
                end
            end

            IGNORED_NODES = %w{Method OperatorMethod Destructor Constructor Function OperatorFunction}.to_set

            def load(required_files, xml)
                @info = GCCXMLInfo.new(required_files)
                info.parse(xml)

                all_types = Array.new
                all_typedefs = Array.new
                info.required_files.each_value do |file_id|
                    all_types.concat(info.types_per_file[file_id])
                    all_typedefs.concat(info.typedefs_per_file[file_id])
                end

                @registry = Registry.new
                # Resolve the real name of '/std/string'
                resolve_std_string
                base_registry = @registry.dup
                @permanent_aliases = Set.new

                if !opaques.empty?
                    # We MUST emit the opaque definitions before calling
                    # resolve_opaques as resolve_opaques will add the resolved
                    # opaque names to +opaques+
                    opaques.each do |type_name|
                        registry.create_opaque type_name, 0
                    end
                    resolve_opaques
                end

                # Resolve structs and classes
                all_types.each do |node|
                    resolve_type_definition(node)
                end

                # Look at typedefs
                all_typedefs.each do |node|
                    resolve_type_definition(node)
                end

                # Now, parse documentation for every type and field for which we
                # have a source file/line
                registry.each do |type|
                    if location = type.metadata.get('source_file_line').first
                        file, line = location.split(':')
                        line = Integer(line)
                        if doc = GCCXMLLoader.parse_cxx_documentation_before(source_file_content(file), line)
                            type.metadata.set('doc', doc)
                        end
                    end
                    if type <= CompoundType
                        type.each do |field|
                            if location = field.metadata.get('source_file_line').first
                                file, line = location.split(':')
                                line = Integer(line)
                                if doc = GCCXMLLoader.parse_cxx_documentation_before(source_file_content(file), line)
                                    field.metadata.set('doc', doc)
                                end
                            end
                        end
                    end
                end

                filtered_registry = ModelKit::Types::Registry.new
                registry.each do |t|
                    if !base_registry.include?(t.name)
                        filtered_registry.merge(t.minimal_registry(with_aliases: false))
                    end
                end
                registry.each(with_aliases: true) do |name, t|
                    next if (name == t.name) || !filtered_registry.include?(t.name)
                    next if base_registry.include?(name)

                    if permanent_alias?(name)
                        filtered_registry.create_alias(name, t.name)
                    end
                end
                filtered_registry
            end

            def permanent_alias?(name)
                permanent_aliases.include?(name)
            end

            def register_permanent_alias(name)
                permanent_aliases << name
            end

            class << self
                # Set of options that should be passed to the gccxml binary
                #
                # it is usually a set of options required to workaround the
                # limitations of gccxml, as e.g. passing -DEIGEN_DONT_VECTORIZE when
                # importing the Eigen headers
                #
                # @return [Array]
                attr_reader :gccxml_default_options
                attr_reader :castxml_default_options
            end
            @gccxml_default_options = Shellwords.split(ENV['TYPELIB_GCCXML_DEFAULT_OPTIONS'] || '-DEIGEN_DONT_VECTORIZE')
            @castxml_default_options = Shellwords.split(ENV['TYPELIB_CASTXML_DEFAULT_OPTIONS'] || '')

            #figure out the correct gccxml binary name, debian has changed this name 
            #to gccxml.real
            def self.gcc_binary_name
                if !`which gccxml.real > /dev/null 2>&1`.empty?
                    return "gccxml.real"
                end
                return "gccxml"
            end

            def self.castxml_binary_name
                ENV['CASTXML'] || 'castxml'
            end

            # Runs castxml on the provided file and with the given options, and
            # return the Nokogiri::XML object representing the result
            #
            # Raises RuntimeError if casrxml failed to run
            def self.castxml(file, required_files: [file], rawflags: Array.new, define: Array.new, include_paths: Array.new)
                cmdline = [castxml_binary_name, *castxml_default_options, "--castxml-gccxml", '-x', 'c++']
                cmdline.concat(rawflags)
                define.each do |str|
                    cmdline << "-D#{str}"
                end
                include_paths.each do |str|
                    cmdline << "-I#{str}"
                end

                required_files.map do |file|
                    Tempfile.open('typelib_gccxml') do |io|
                        if !system(*cmdline, '-o', io.path, file)
                            raise ArgumentError, "castxml returned an error while parsing #{file} with call #{cmdline.join(' ')}"
                        end
                        io.open
                        io.read
                    end
                end
            end
            # Runs gccxml on the provided file and with the given options, and
            # return the Nokogiri::XML object representing the result
            #
            # Raises RuntimeError if gccxml failed to run
            def self.gccxml(file, required_files: [file], rawflags: Array.new, define: Array.new, include_paths: Array.new)
                cmdline = [gcc_binary_name, *gccxml_default_options]
                cmdline.concat(rawflags)
                define.each do |str|
                    cmdline << "-D#{str}"
                end
                include_paths.each do |str|
                    cmdline << "-I#{str}"
                end

                cmdline << file

                Tempfile.open('typelib_gccxml') do |io|
                    cmdline << "-fxml=#{io.path}"
                    if !system(*cmdline)
                        raise ArgumentError, "gccxml returned an error while parsing #{file} with call #{cmdline.join(' ')}"
                    end
                    [io.read]
                end
            end

            def self.import(file, registry: Registry.new, castxml: false, opaques: Set.new, required_files: [file], include_paths: Array.new, define: Array.new, rawflags: Array.new, **options)
                include_paths.concat(options.fetch(:include, Array.new).to_a)
                required_files = required_files.map { |f| File.expand_path(f) }

                registry_opaques = Set.new
                registry.each do |type|
                    if type.opaque?
                        registry_opaques << type.name
                    end
                end

                raw_xml = if castxml then castxml(file, required_files: required_files, rawflags: rawflags, define: define, include_paths: include_paths)
                          else gccxml(file, required_files: required_files, rawflags: rawflags, define: define, include_paths: include_paths)
                          end

                raw_xml.each do |xml|
                    converter = GCCXMLLoader.new
                    converter.opaques = registry_opaques.dup | opaques.to_set
                    gccxml_registry = converter.load(required_files, xml)
                    registry.merge(gccxml_registry)
                end
            end

            def self.preprocess(files, castxml: false, include_paths: Array.new, define: Array.new, **options)
                if options[:include]
                    include_paths.concat(options[:include].to_a)
                end
                includes = include_paths.map { |v| "-I#{v}" }
                defines  = define.map { |v| "-D#{v}" }

                Tempfile.open(['orogen_gccxml_input','.hpp']) do |io|
                    files.each do |path|
                        io.puts "#include <#{path}>"
                    end
                    io.flush

                    if castxml
                        call = [castxml_binary_name, "--castxml-gccxml", "-E", *includes, *defines, *castxml_default_options, io.path] 
                    else
                        call = [gcc_binary_name, "--preprocess", *includes, *defines, *gccxml_default_options, io.path]
                    end

                    result = IO.popen(call) do |gccxml_io|
                        gccxml_io.read
                    end

                    if !$?.success?
                        raise ArgumentError, "failed to preprocess #{files.join(" ")} \"#{call[0..-1].join(" ")} /tmp/gcc-debug\""
                    end

                    result
                end
            end
        end
    end
end

