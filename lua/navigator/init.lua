local has_telescope = pcall(require, 'telescope')
if not has_telescope then
  error('This plugin requires nvim-telescope/telescope.nvim')
end

if vim.fn.has("nvim-0.9") ~= 1 then
  error "This plugin requires at least Neovim 0.9"
end

local M = {}

local function inlist(symbol, symbol_list)
  -- Empty symbol list means all symbols
  if not symbol_list or #symbol_list == 0 then
    return true
  end

  for _, value in ipairs(symbol_list) do
    if string.match(symbol, value) then
      return true
    end
  end
  return false
end

local function get_regex_symbols(languages, query_list)
  local file_symbols = {}
  for _, language in ipairs(languages) do
    local symbols = {}
    for _, query in ipairs(query_list) do
      if query.parser == language and query.regex and query.regex ~= '' then
        -- Store all the captures in the query
        -- Remove possible duplicates in symbols (different queries for the
        -- same language sharing some captures)
        for _, regex in ipairs(query.regex) do
          symbols[regex.name] = 1
        end
      end
    end
    -- Copy the list of unique symbols
    local usymbols = {}
    for k, _ in pairs(symbols) do
      table.insert(usymbols, k)
    end
    if #usymbols > 0 then
      table.insert(file_symbols, { language = language, symbols = usymbols })
    end
  end
  return file_symbols
end

local function get_ts_symbols(languages, query_list)
  local file_symbols = {}
  for _, language in ipairs(languages) do
    local symbols = {}
    for _, query in ipairs(query_list) do
      if query.parser == language and query.query and query.query ~= '' then
        local parsed = vim.treesitter.query.parse(language, query.query)
        -- Store all the captures in the query
        -- Remove possible duplicates in symbols (different queries for the
        -- same language sharing some captures)
        for _, capture in ipairs(parsed.captures) do
          symbols[capture] = 1
        end
      end
    end
    -- Copy the list of unique symbols
    local usymbols = {}
    for k, _ in pairs(symbols) do
      table.insert(usymbols, k)
    end
    if #usymbols > 0 then
      table.insert(file_symbols, { language = language, symbols = usymbols })
    end
  end
  return file_symbols
end

local function get_symbols(bufnr, query_list)
  -- Get languages in buffer
  local languages = {}
  -- Get file parser
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    languages = { vim.bo[bufnr].filetype }
  else
    -- Do I need to re-parse? If there are no changes, parsing should be free
    local _ = file_parser:parse()
    file_parser:for_each_child(function(ltree, language)
      table.insert(languages, language)
    end, true)
  end
  -- Get all the symbols for each language
  local symbols = get_ts_symbols(languages, query_list)
  local regex_symbols = get_regex_symbols(languages, query_list)
  for _,v in ipairs(regex_symbols) do
    table.insert(symbols, v)
  end

  -- Merge tables
  local file_symbols = {}
  local done = {}
  for _, v in ipairs(symbols) do
    if done[v.language] == nil then
      done[v.language] = {}
      file_symbols[v.language] = {}
    end
    for _, symbol in ipairs(v.symbols) do
      if done[v.language][symbol] == nil then
        done[v.language][symbol] = true
        table.insert(file_symbols[v.language], symbol)
      end
    end
  end
  return file_symbols
end

local function get_regex_query_results(bufnr, buf_languages, query_list, language_list, symbol_list)
  local data = {}

  local regexes = {}
  for _, language in ipairs(buf_languages) do
    if inlist(language, language_list) then
      for _, query in ipairs(query_list) do
        if query.parser == language and query.regex and query.regex ~= '' then
          for _, regex in ipairs(query.regex) do
            if inlist(regex.name, symbol_list) then
              local cregex = vim.regex(regex.expr)
              if cregex then
                table.insert(regexes, { language = language, name = regex.name, expr = cregex })
              end
            end
          end
        end
      end
    end
  end
  if #regexes > 0 then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for row, text in ipairs(lines) do
      for _, regex in ipairs(regexes) do
        local scol, ecol = regex.expr:match_str(text)
        if scol then
          table.insert(data, { language = regex.language,
            range = { srow = row - 1, scol = scol, erow = row - 1, ecol = ecol },
            text = text, symbol = regex.name })
        end
      end
    end
  end
  return data
end

local function get_ts_query_results(bufnr, query_list, language_list, symbol_list)
  local data = {}
  local last = -1

  -- Get file parser
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return data
  end

  -- Get all the languages in the buffer
  -- Do I need to re-parse? Even if called, it should be cached, so no overhead
  local _ = file_parser:parse()
  file_parser:for_each_child(function(ltree, language)
    if inlist(language, language_list) then
      ltree:for_each_tree(function(tree, _)
        for _, query in ipairs(query_list) do
          if query.parser == language and query.query and query.query ~= '' then
            local parsed = vim.treesitter.query.parse(language, query.query)
            for _, matches, _ in parsed:iter_matches(tree:root(), bufnr, 0, last) do
              for id, match in pairs(matches) do
                local symbol = parsed.captures[id]
                if inlist(symbol, symbol_list) then
                  local srow, scol, erow, ecol = match:range(false)
                  local text = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, false)[1]
                  table.insert(data, { language = language,
                    range = { srow = srow, scol = scol, erow = erow, ecol = ecol },
                    text = text, symbol = symbol })
                end
              end
            end
          end
        end
      end)
    end
  end, true)

  return data
end

local function get_query_results(bufnr, query_list, language_list, symbol_list)
  -- Get languages in buffer
  local languages = {}
  -- Get file parser
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    languages = { vim.bo[bufnr].filetype }
  else
    -- Do I need to re-parse? If there are no changes, parsing should be free
    local _ = file_parser:parse()
    file_parser:for_each_child(function(ltree, language)
      table.insert(languages, language)
    end, true)
  end

  local query_data = get_ts_query_results(bufnr, query_list, language_list, symbol_list)
  local regex_query_data = get_regex_query_results(bufnr, languages, query_list, language_list, symbol_list)
  for _, v in ipairs(regex_query_data) do
    table.insert(query_data, v)
  end

  -- Merge tables by row
  local data = {}
  for _, v in ipairs(query_data) do
    table.insert(data, v)
  end
  -- Sort table by row
  table.sort(data, function(a, b)
    if a.range.srow < b.range.srow then
      return true
    elseif
      a.range.srow == b.range.srow then
      if a.range.scol < b.range.scol then
        return true
      else
        return false
      end
    end
    return false
  end)

  return data
end


local function get_ts_highlights(bufnr)
  local hls = {}
  local last = -1

  -- Get file parser
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return hls
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = 1, #lines do
    hls[i] = {}
  end
  -- Get all the languages in the buffer
  -- Do I need to re-parse? Even if called, it should be cached, so no overhead
  local _ = file_parser:parse()
  file_parser:for_each_child(function(ltree, language)
    ltree:for_each_tree(function(tree, _)
      local parsed = vim.treesitter.query.get(language, "highlights")
      if parsed then
        for id, node, metadata in parsed:iter_captures(tree:root(), bufnr, 0, last) do
          local hl = parsed.captures[id]
          if hl ~= 'spell' then
            local srow, scol, erow, ecol = node:range(false)
            local priority = (tonumber(metadata.priority) or 100)
            -- Overwrite with same priority, like Neovim does
            if srow == erow then
              local row = srow
              for index = scol, ecol - 1 do
                if not hls[row + 1][index] or hls[row + 1][index].priority <= priority then
                  hls[row + 1][index] = { priority = priority, hl_group = hl }
                end
              end
            else
              local row = srow
              for index = scol, #lines[row + 1] - 1 do
                if not hls[row + 1][index] or hls[row + 1][index].priority <= priority then
                  hls[row + 1][index] = { priority = priority, hl_group = hl }
                end
              end
              while row < erow do
                row = row + 1
                local col
                if row < erow then
                  col = #lines[row + 1] - 1
                else
                  -- ecol is exclusive
                  col = ecol - 1
                end
                for index = 0, col do
                  if hls[row + 1] == nil then
                    print('Error')
                  end
                  if not hls[row + 1][index] or hls[row + 1][index].priority <= priority then
                    hls[row + 1][index] = { priority = priority, hl_group = hl }
                  end
                end
              end
            end
          end
        end
      end
    end)
  end, true)

  return hls
end

local entry_display = require("telescope.pickers.entry_display")
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local previewers = require "telescope.previewers"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"


M.navigate = function(opts)
  local bufnr = vim.fn.bufnr()

  -- For previewer highlighting
  local namespace = vim.api.nvim_create_namespace("Navigator")

  local language_list = {}
  if opts and opts.language_list then
    language_list = opts.language_list
  end
  local symbol_list = {}
  if opts and opts.symbol_list then
    symbol_list = opts.symbol_list
  end
  local query_list = {}
  if opts and opts.query_list then
    query_list = opts.query_list
  else
    query_list = require('navigator.queries').queries
  end

  local symbols_data = get_symbols(bufnr, query_list)
  -- Create a structure with 'enabled' languages and symbols that can be updated
  -- by the pickers
  local selected_languages = {}
  local selected_symbols = {}
  -- Flat table for pickers
  local languages = {}
  local symbols = {}
  for language, v in pairs(symbols_data) do
    table.insert(languages, { language = language })
    selected_languages[language] = true
    selected_symbols[language] = {}
    for _, symbol in ipairs(v) do
      selected_symbols[language][symbol] = true
      table.insert(symbols, { language = language, symbol = symbol })
    end
  end

  local results = get_query_results(bufnr, query_list, language_list, symbol_list)

  local highlights = get_ts_highlights(bufnr)

  local language_displayer = entry_display.create {
    separator = " │ ",
    items = {
      { remaining = true },
    },
  }

  local make_language_display = function(data)
    return language_displayer {
      { data.value.language or "", "Comment" },
    }
  end

  local symbols_displayer = entry_display.create {
    separator = " │ ",
    items = {
      { width = 30 },
      { remaining = true },
    },
  }

  local make_symbols_display = function(data)
    return symbols_displayer {
      { data.value.language or "", "Comment" },
      { data.value.symbol or "", "Function" },
    }
  end

  local query_displayer = entry_display.create {
    separator = " │ ",
    items = {
      { width = 10 },
      { width = 30 },
      { remaining = true },
    },
  }

  local make_query_display = function(data)
    return query_displayer {
      { data.value.range.srow or "", "Comment" },
      { data.value.symbol or "", "Function" },
      {
        data.value.text or "",
        function()
          local hl_results = {}
          for col, hl in pairs(highlights[data.value.range.srow + 1]) do
            table.insert(hl_results, { { col, col + 1 }, '@' .. hl.hl_group })
          end
          return hl_results
        end,
      },
    }
  end

  local main_finder = function(opts)
    return finders.new_table({
      results = results,
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        if not selected_languages[entry.language] then
          return
        end
        if not selected_symbols[entry.language][entry.symbol] then
          return
        end
        local result = {}
        result.value = entry
        result.display = make_query_display
        result.ordinal = result.value.text
        return result
      end,
    })
  end

  local language_finder = function(opts)
    return finders.new_table({
      results = languages,
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        local result = {}
        result.value = entry
        result.display = make_language_display
        result.ordinal = result.value.language
        return result
      end,
    })
  end

  local symbols_finder = function(opts)
    return finders.new_table({
      results = symbols,
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        local result = {}
        result.value = entry
        result.display = make_symbols_display
        result.ordinal = result.value.symbol
        return result
      end,
    })
  end

  local language_picker, symbols_picker, main_picker
  local language_picker_prompt = 'Select Languages'
  local symbols_picker_prompt = "Select Symbols"
  local main_picker_prompt = "Treesitter Symbols"

  local function select_languages(prompt_bufnr)
    local spicker = action_state.get_current_picker(prompt_bufnr)
    if spicker.prompt_title == symbols_picker_prompt then
      -- Filter symbol selection
      -- If multi-selection, use those values, otherwise choose the selected entry
      local selections = #spicker:get_multi_selection() > 0 and spicker:get_multi_selection() or { action_state.get_selected_entry() }
      -- Update symbol selection
      for k, _ in pairs(selected_symbols) do
        for s, _ in pairs(selected_symbols[k]) do
          selected_symbols[k][s] = false
        end
      end
      for _, selection in ipairs(selections) do
        selected_symbols[selection.value.language][selection.value.symbol] = true
      end
      -- Update related languages from symbol list
      for k, _ in pairs(selected_symbols) do
        local lang = false
        for s, _ in pairs(selected_symbols[k]) do
          lang = lang or selected_symbols[k][s]
        end
        selected_languages[k] = lang
      end
    end
    local picker = language_picker(opts)
    picker:find()
  end

  local function select_symbols(prompt_bufnr)
    local spicker = action_state.get_current_picker(prompt_bufnr)
    if spicker.prompt_title == language_picker_prompt then
      -- Get the selection and update selection tables
      -- If multi-selection, use those values, otherwise choose the selected entry
      local selections = #spicker:get_multi_selection() > 0 and spicker:get_multi_selection() or { action_state.get_selected_entry() }
      -- Update language selection
      for k, _ in pairs(selected_languages) do
        selected_languages[k] = false
      end
      for _, selection in ipairs(selections) do
        selected_languages[selection.value.language] = true
      end
      -- Update related symbols
      for k, _ in pairs(selected_languages) do
        if not selected_languages[k] then
          for s, _ in pairs(selected_symbols[k]) do
            selected_symbols[k][s] = false
          end
        end
      end
    end

    local picker = symbols_picker(opts)
    picker:find()
  end

  --local function navigate_from_symbols(prompt_bufnr)
  local function navigate(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    if picker.prompt_title == symbols_picker_prompt then
      -- Filter symbol selection
      -- If multi-selection, use those values, otherwise choose the selected entry
      local selections = #picker:get_multi_selection() > 0 and picker:get_multi_selection() or { action_state.get_selected_entry() }
      -- Update symbol selection
      for k, _ in pairs(selected_symbols) do
        for s, _ in pairs(selected_symbols[k]) do
          selected_symbols[k][s] = false
        end
      end
      for _, selection in ipairs(selections) do
        selected_symbols[selection.value.language][selection.value.symbol] = true
      end
    elseif picker.prompt_title == language_picker_prompt then
      -- Filter language selection
      -- If multi-selection, use those values, otherwise choose the selected entry
      local selections = #picker:get_multi_selection() > 0 and picker:get_multi_selection() or { action_state.get_selected_entry() }
      -- Update language selection
      for k, _ in pairs(selected_languages) do
        selected_languages[k] = false
      end
      for _, selection in ipairs(selections) do
        selected_languages[selection.value.language] = true
      end
    end
    main_picker(opts):find()
  end

  symbols_picker = function(opts)
    return pickers.new(opts, {
      prompt_title = symbols_picker_prompt,
      finder = symbols_finder(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function() return end)
        map('i', '<C-l>', select_languages)
        map('i', '<C-n>', navigate)
        return true
      end,
      sorter = conf.generic_sorter(opts),
      on_complete = {
        function(picker)
          local entry_manager = picker.manager
          local num = entry_manager:num_results()
          --for row = 1, entry_manager:num_results() do
          for row = 0, num do
            local idx = picker:get_index(row)
            local entry = entry_manager:get_entry(idx)
            if selected_symbols[entry.value.language][entry.value.symbol] then
              picker:add_selection(row)
            end
          end
        end
      }
    })
  end

  language_picker = function(opts)
    return pickers.new(opts, {
      prompt_title = language_picker_prompt,
      finder = language_finder(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function() return end)
        map('i', '<C-s>', select_symbols)
        map('i', '<C-n>', navigate)
        return true
      end,
      sorter = conf.generic_sorter(opts),
      on_complete = {
        function(picker)
          local entry_manager = picker.manager
          local num = entry_manager:num_results()
          for row = 0, num do
            local idx = picker:get_index(row)
            local entry = entry_manager:get_entry(idx)
            if selected_languages[entry.value.language] then
              picker:add_selection(row)
            end
          end
        end
      }
    })
  end


  local function main_previewer(opts)
    opts = opts or {}

    return previewers.new_buffer_previewer {
      title = "Navigator",
      get_buffer_by_name = function(self, entry)
        -- Assign the same name so the buffer is cached and we don't reload
        -- the contents for each entry
        return "Navigator"
      end,
      define_preview = function(self, entry, status)
        -- Copy buffer contents if not loaded before
        if self.state.bufname == nil then
          local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, true, buffer_lines)
          -- Copy filetype
          local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
          vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', filetype)
        end
        -- sometimes, without pcall, the function errs (?). Maybe the window is
        -- not ready yet when moving from symbols to navigate
        pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.value.range.srow + 1, entry.value.range.scol })
        vim.api.nvim_buf_call(self.state.bufnr, function()
          vim.cmd "norm! zz"
        end)
        -- highlight symbol
        vim.api.nvim_buf_clear_namespace(self.state.bufnr, namespace, 0, -1)
        if entry.value.range.srow == entry.value.range.erow then
          local row = entry.value.range.srow
          vim.api.nvim_buf_add_highlight(self.state.bufnr, namespace, "TelescopePreviewLine",
            row, entry.value.range.scol, entry.value.range.ecol)
        else
          local row = entry.value.range.srow
          vim.api.nvim_buf_add_highlight(self.state.bufnr, namespace, "TelescopePreviewLine",
            row, entry.value.range.scol, -1)
          while row < entry.value.range.erow do
            row = row + 1
            if row < entry.value.range.erow then
              vim.api.nvim_buf_add_highlight(self.state.bufnr, namespace, "TelescopePreviewLine",
                row, 0, -1)
            else
              vim.api.nvim_buf_add_highlight(self.state.bufnr, namespace, "TelescopePreviewLine",
                row, 0, entry.value.range.ecol)
            end
          end
        end
      end,
    }
  end

  -- Start Telescope prompt with query
  main_picker = function(opts)
    return pickers.new(opts, {
      prompt_title = main_picker_prompt,
      finder = main_finder(opts),
      attach_mappings = function(prompt_bufnr, map)
        map('i', '<C-l>', select_languages)
        map('i', '<C-s>', select_symbols)
        return true
      end,
      --previewer = conf.grep_previewer(opts),
      previewer = main_previewer(opts),
      sorter = conf.file_sorter(opts),
    })
  end

  main_picker(opts):find()
end

return M
