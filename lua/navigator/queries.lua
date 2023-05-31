local M = {}

-- Read file into string
M.read_file = function(filename)
  local text = nil
  local f, err = io.open(filename, "r")
  if f then
    text = f:read("*a")
    f:close()
  else
    error(err)
  end
  return text
end

local header_query =
[[
[
  (atx_heading (atx_h1_marker))
  (atx_heading (atx_h2_marker))
  (atx_heading (atx_h3_marker))
  (atx_heading (atx_h4_marker))
  (atx_heading (atx_h5_marker))
  (atx_heading (atx_h6_marker))
  (setext_heading (setext_h1_underline))
  (setext_heading (setext_h2_underline))
  ] @definition.header

  ((atx_heading (atx_h1_marker)) @definition.header.h1)
  ((atx_heading (atx_h2_marker)) @definition.header.h2)
  ((atx_heading (atx_h3_marker)) @definition.header.h3)
  ((atx_heading (atx_h4_marker)) @definition.header.h4)
  ((atx_heading (atx_h5_marker)) @definition.header.h5)
  ((atx_heading (atx_h6_marker)) @definition.header.h6)
  ((setext_heading (setext_h1_underline)) @definition.header.h1)
  ((setext_heading (setext_h2_underline)) @definition.header.h2)
]]

local tag_query =
  [[
  (tag) @definition.tag
  ]]

local tag_regex = [[#[a-zA-Z_\-\/][0-9a-zA-Z_\-\/]*]]


M.queries = {
  {
    parser = 'markdown',
    query = header_query,
    regex = {
      { name = 'definition.regex_tag', expr = tag_regex },
    }
  },
  {
    parser = 'markdown_inline',
    query = tag_query,
  },
  {
    parser = 'lua',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'lua', 'locals'), true)[1]),
  },
  --{
  --  parser = 'cpp',
  --  query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'cpp', 'locals'), true)[1]),
  --},
  {
    parser = 'cpp',
    query = [[
      (function_declarator
       declarator: (field_identifier) @method)
      (destructor_name
       (identifier) @method)
      (function_declarator                                                                                                                                                        
       (template_method                                                                                                                                                          
        (field_identifier) @method))                                                                                                                                            
      (call_expression                                                                                                                                                            
       (field_expression                                                                                                                                                         
        (field_identifier) @method.call))
      ; functions                                                                                                                                                                 
      (function_declarator                                                                                                                                                        
       (identifier) @function)                                                                                                                                                
      (function_declarator                                                                                                                                                        
       (qualified_identifier                                                                                                                                                     
        (identifier) @function))                                                                                                                                                
      (function_declarator                                                                                                                                                        
       (qualified_identifier                                                                                                                                                     
        (qualified_identifier                                                                                                                                                   
         (identifier) @function)))                                                                                                                                             
      (function_declarator                                                                                                                                                        
       (qualified_identifier                                                                                                                                                     
        (qualified_identifier                                                                                                                                                   
         (qualified_identifier                                                                                                                                                 
          (identifier) @function))))                                                                                                                                          
      ((qualified_identifier                                                                                                                                                      
       (qualified_identifier                                                                                                                                                     
        (qualified_identifier                                                                                                                                                   
         (qualified_identifier                                                                                                                                                 
          (identifier) @function)))) @_parent                                                                                                                                 
       (#has-ancestor? @_parent function_declarator))                                                                                                                            
                                                                                                                                                                              
      (function_declarator                                                                                                                                                        
       (template_function                                                                                                                                                        
        (identifier) @function))
    ]],
  },
  {
    parser = 'c',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'c', 'locals'), true)[1]),
  },
  {
    parser = 'cuda',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'cuda', 'locals'), true)[1]),
  },
  {
    parser = 'dart',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'dart', 'locals'), true)[1]),
  },
  {
    parser = 'fennel',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'fennel', 'locals'), true)[1]),
  },
  {
    parser = 'go',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'go', 'locals'), true)[1]),
  },
  {
    parser = 'html',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'html', 'locals'), true)[1]),
  },
  {
    parser = 'javascript',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'javascript', 'locals'), true)[1]),
  },
  {
    parser = 'json',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'json', 'locals'), true)[1]),
  },
  {
    parser = 'julia',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'julia', 'locals'), true)[1]),
  },
  {
    parser = 'pascal',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'pascal', 'locals'), true)[1]),
  },
  {
    parser = 'php',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'php', 'locals'), true)[1]),
  },
  {
    parser = 'python',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'python', 'locals'), true)[1]),
  },
  {
    parser = 'rst',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'rst', 'locals'), true)[1]),
  },
  {
    parser = 'ruby',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'ruby', 'locals'), true)[1]),
  },
  {
    parser = 'rust',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'rust', 'locals'), true)[1]),
  },
  {
    parser = 'vim',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'vim', 'locals'), true)[1]),
  },
  {
    parser = 'yaml',
    query = M.read_file(vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", 'yaml', 'locals'), true)[1]),
  },
}

return M
