#pragma once

#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_dart.h is a section of ingest.cpp; include it only there"
#endif

namespace rw
{
namespace
{

inline TSNode dartFindDescendant( TSNode root, const char* want )
{
    if( ts_node_is_null( root ) )
    {
        return {};
    }
    std::vector<TSNode> stack;
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode node = stack.back();
        stack.pop_back();
        if( std::strcmp( ts_node_type( node ), want ) == 0 )
        {
            return node;
        }
        for( std::uint32_t i = ts_node_named_child_count( node ); i > 0; --i )
        {
            stack.push_back( ts_node_named_child( node, i - 1 ) );
        }
    }
    return {};
}

inline std::string dartQuotedText( TSNode node, std::string_view src )
{
    std::string_view s = nodeTextOf( node, src );
    if( s.size() >= 2 && ( s.front() == '\'' || s.front() == '"' ) && s.back() == s.front() )
    {
        s = s.substr( 1, s.size() - 2 );
    }
    return std::string( s );
}

inline std::string dartUriText( TSNode node, std::string_view src )
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const char* t = ts_node_type( node );
    if( std::strcmp( t, "configurable_uri" ) == 0 )
    {
        for( std::uint32_t i = 0; i < ts_node_named_child_count( node ); ++i )
        {
            const TSNode child = ts_node_named_child( node, i );
            if( std::strcmp( ts_node_type( child ), "uri" ) == 0 )
            {
                return dartUriText( child, src );
            }
        }
        return {};
    }
    if( std::strcmp( t, "configuration_uri" ) == 0 )
    {
        if( const TSNode uri = ts_node_child_by_field_name( node, "uri", 3 ); !ts_node_is_null( uri ) )
        {
            return dartUriText( uri, src );
        }
    }
    if( std::strcmp( t, "uri" ) == 0 )
    {
        for( std::uint32_t i = 0; i < ts_node_named_child_count( node ); ++i )
        {
            const TSNode child = ts_node_named_child( node, i );
            if( std::strcmp( ts_node_type( child ), "string_literal" ) == 0 )
            {
                return dartQuotedText( child, src );
            }
        }
        return {};
    }
    if( std::strcmp( t, "string_literal" ) == 0 )
    {
        return dartQuotedText( node, src );
    }
    if( std::strcmp( t, "dotted_identifier_list" ) == 0 )
    {
        return std::string( nodeTextOf( node, src ) );
    }
    if( const TSNode quoted = dartFindDescendant( node, "string_literal" ); !ts_node_is_null( quoted ) )
    {
        return dartQuotedText( quoted, src );
    }
    if( const TSNode dotted = dartFindDescendant( node, "dotted_identifier_list" ); !ts_node_is_null( dotted ) )
    {
        return std::string( nodeTextOf( dotted, src ) );
    }
    return {};
}

inline std::string dartDirectiveTarget( TSNode node, std::string_view src )
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const char* t = ts_node_type( node );
    if( std::strcmp( t, "library_import" ) == 0 )
    {
        return dartUriText( dartFindDescendant( node, "uri" ), src );
    }
    if( std::strcmp( t, "library_export" ) == 0 )
    {
        return dartUriText( dartFindDescendant( node, "uri" ), src );
    }
    if( std::strcmp( t, "part_directive" ) == 0 )
    {
        return dartUriText( dartFindDescendant( node, "uri" ), src );
    }
    if( std::strcmp( t, "part_of_directive" ) == 0 )
    {
        if( const TSNode uri = dartFindDescendant( node, "uri" ); !ts_node_is_null( uri ) )
        {
            return dartUriText( uri, src );
        }
        return dartUriText( dartFindDescendant( node, "dotted_identifier_list" ), src );
    }
    return {};
}

inline std::vector<std::string> dartConditionalTargets( TSNode node, std::string_view src )
{
    std::vector<std::string> out;
    if( ts_node_is_null( node ) )
    {
        return out;
    }
    std::vector<TSNode> stack;
    stack.push_back( node );
    while( !stack.empty() )
    {
        const TSNode cur = stack.back();
        stack.pop_back();
        if( std::strcmp( ts_node_type( cur ), "configuration_uri" ) == 0 )
        {
            if( std::string uri = dartUriText( cur, src ); !uri.empty()
                && std::find( out.begin(), out.end(), uri ) == out.end() )
            {
                out.push_back( std::move( uri ) );
            }
        }
        for( std::uint32_t i = ts_node_named_child_count( cur ); i > 0; --i )
        {
            stack.push_back( ts_node_named_child( cur, i - 1 ) );
        }
    }
    return out;
}

inline std::string dartEnclosingScopeOf( TSNode node, std::string_view src )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        const bool  scopeOwner =    std::strcmp( t, "class_declaration" ) == 0 || std::strcmp( t, "mixin_declaration" ) == 0
                                 || std::strcmp( t, "extension_declaration" ) == 0 || std::strcmp( t, "extension_type_declaration" ) == 0
                                 || std::strcmp( t, "enum_declaration" ) == 0;
        if( !scopeOwner )
        {
            continue;
        }
        const TSNode nm = ts_node_child_by_field_name( p, "name", 4 );
        if( ts_node_is_null( nm ) )
        {
            return {};
        }
        if( std::strcmp( ts_node_type( nm ), "extension_type_name" ) == 0 && ts_node_named_child_count( nm ) > 0 )
        {
            return std::string( nodeTextOf( ts_node_named_child( nm, 0 ), src ) );
        }
        return std::string( nodeTextOf( nm, src ) );
    }
    return {};
}

} // namespace
} // namespace rw
