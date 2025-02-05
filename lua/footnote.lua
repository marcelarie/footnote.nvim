local M = {}

--- get the next foootnote number that need to added based on existing footnotes
---@param buffer table contains the entire buffer
---@return number next_footnote next footnote number
local function get_next_footnote_number(buffer)
  local max_num = 0
  for _, line in ipairs(buffer) do
    for match in string.gmatch(line, '%[%^%d+]') do
      local num = tonumber(string.match(match, '%d+'))
      if num and num > max_num then
        max_num = num
      end
    end
  end
  return max_num + 1
end

--- get the index of end of the word the cursor is on
---@param bufnr number buffer number ("0" for current buffer)
---@param row number row of the cursor
---@param col number col of the cursor
---@return number col the col of the end of the word
local function get_word_end(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
  local word_end = col
  while word_end < #line and line:sub(word_end + 1, word_end + 1):match '%w' do
    word_end = word_end + 1
  end
  return word_end
end

--- check if a given location is on a footnote reference
---@param buffer table the buffer to check
---@param row number the row of the given location
---@param col number the col of the given location
---@return number | nil col the start col of the footnote. If not on a footnote, return nil
local function is_on_ref(buffer, row, col)
  local line = buffer[row]
  local refColStart = 0
  local refColEnd = 0
  while true do
    refColStart, refColEnd = string.find(line, '%[%^%d+]', refColStart + 1)
    if refColStart == nil then
      break
    elseif refColStart <= col and col < refColEnd then
      return refColStart - 1
    end
  end
  return nil
end

--- Get the existing footnote number for a word if it has already been referenced
---@param buffer table the entire buffer
---@param word string the word to check
---@return number | nil footnote_num the existing footnote number, or nil if not found
local function get_existing_footnote(buffer, word)
  for _, line in ipairs(buffer) do
    local match = string.match(line, '(%S+)%[%^(%d+)%]')
    if match and match == word then
      return tonumber(string.match(line, '%[%^(%d+)%]'))
    end
  end
  return nil
end

--- Automatically reference an existing footnote if the word has already been referenced
---@param word string the word under cursor
---@param row number the cursor row
---@param col number the cursor column
---@return boolean true if referenced existing footnote, false otherwise
local function auto_reference_existing_footnote(word, row, col)
  local buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_footnote = get_existing_footnote(buffer, word)
  if existing_footnote then
    local footnote_ref = string.format('[^%d]', existing_footnote)
    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { footnote_ref })
    print('Referenced existing footnote: ' .. existing_footnote)
    return true
  end
  return false
end

function M.auto_reference_all()
  local buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local word_references = {}

  -- Gather known footnotes: which word has which footnote number?
  for _, line in ipairs(buffer) do
    for word, footnote in string.gmatch(line, '(%S+)%[%^(%d+)%]') do
      word_references[word] = tonumber(footnote)
    end
  end

  -- For each line, iterate over all words and insert the appropriate footnote if needed
  for row, line in ipairs(buffer) do
    local updated_line = line
    local offset = 1

    while true do
      -- Find the next word in the line, starting from `offset`
      local s, e = string.find(updated_line, '(%S+)', offset)
      if not s then
        break
      end

      local word = updated_line:sub(s, e)
      local footnote_num = word_references[word]

      if footnote_num then
        -- Check if this occurrence is already followed by a footnote
        -- by peeking ahead for `[^digit]` right after the word.
        local after = updated_line:sub(e + 1, e + 4)
        local already_footnoted = after:match '^%[%^%d+%]'

        if not already_footnoted then
          local footnote_ref = ('[^%d]'):format(footnote_num)
          -- Insert the footnote reference immediately after the word
          updated_line = updated_line:sub(1, e) .. footnote_ref .. updated_line:sub(e + 1)
          -- Advance offset past the newly inserted footnote
          offset = e + #footnote_ref + 1
        else
          -- If it's already footnoted, just move past it
          offset = e + 1
        end
      else
        -- This word has no known footnote, skip it
        offset = e + 1
      end
    end

    -- If we changed the line, update the buffer
    if updated_line ~= line then
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { updated_line })
    end
  end

  print 'Auto-referenced all repeated words with footnotes'
end

-- The main new_footnote function incorporating everything
function M.new_footnote()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]
  local buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local next_num = get_next_footnote_number(buffer)
  local footnote_ref = string.format('[^%d]', next_num)
  local footnote_content = string.format('[^%d]: ', next_num)

  -- check if we need to jump to an existing footnote instead of creating one
  local word_end = is_on_ref(buffer, row, col)
  if word_end == nil then
    word_end = get_word_end(0, row, col)
  end

  local til_end = string.sub(buffer[row], word_end + 1, -1)
  local word_end_ref = string.match(til_end, '^%[%^%d+]')
  if word_end_ref ~= nil then
    local num = tonumber(string.sub(word_end_ref, 3, -2))
    for i = #buffer, 1, -1 do
      local line = buffer[i]
      if string.match(line, '^%[%^' .. num .. ']:') then
        vim.api.nvim_win_set_cursor(0, { i, #word_end_ref + 2 })
        return
      end
    end
    -- if the reference is an orphan, delete it
    vim.api.nvim_buf_set_text(0, row - 1, word_end, row - 1, word_end + #word_end_ref, {})
    return
  elseif string.match(buffer[row], '^%[%^%d+]:') then
    local num = string.match(buffer[row], '%d+')
    -- TODO: add multi references support
    for i, line in ipairs(buffer) do
      local match = string.find(line, '%[%^' .. num .. ']')
      if match ~= nil then
        vim.api.nvim_win_set_cursor(0, { i, match + 1 })
        return
      end
    end
    -- if the footnote is an orphan, delete it
    vim.api.nvim_buf_set_text(0, row - 1, 0, row - 1, -1, {})
    return
  end

  -- Attempt to auto-reference existing footnote if the same word was footnoted
  local word_end_temp = get_word_end(0, row, col)
  local word = string.sub(buffer[row], col + 1, word_end_temp)
  if auto_reference_existing_footnote(word, row, col) then
    return
  end

  -- Otherwise, create a brand new footnote
  vim.api.nvim_buf_set_text(0, row - 1, word_end, row - 1, word_end, { footnote_ref })

  -- Add footnote label to jumplist
  vim.api.nvim_win_set_cursor(0, { row, word_end + string.len(footnote_ref) - 1 })
  vim.cmd 'normal! m`'

  -- Insert footnote reference at the end of the buffer
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { '', footnote_content })
  print 'New footnote created'

  -- Move cursor to the footnote reference
  local line_count = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { line_count, string.len(footnote_content) })
  vim.cmd 'startinsert!'

  if Opts and Opts.organize_on_new then
    M.organize_footnotes()
  end
end

-- We'll keep the rest of the original code after new_footnote (like ref_rename, content_rename, etc) as is.

--- rename all footnote references with given label to another label
---@param bufnr number buffer number
---@param ref_locations table locations of all the footnote references
---@param from number the label to change
---@param to number the label to change to
local function ref_rename(bufnr, ref_locations, from, to)
  if from == to then
    return
  end
  local buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for index = 1, #ref_locations, 1 do
    local location = ref_locations[index]
    if location == nil then
      goto continue
    end
    local label = string.sub(buffer[location[1]], location[2], location[3])
    local number = tonumber(string.sub(label, 3, -2))
    local row = location[1]
    local startCol = location[2]
    local endCol = location[3]

    local shift = 0

    -- swap footnote labels
    if number == from then
      if Opts and Opts.debug_print then
        print('ref_rename: ' .. from .. ' -> ' .. to)
      end
      shift = #tostring(to) - #tostring(from)
      vim.api.nvim_buf_set_text(bufnr, row - 1, startCol + 1, row - 1, endCol - 1, { tostring(to) })
    elseif number == to then
      if Opts and Opts.debug_print then
        print('ref_rename: ' .. to .. ' -> ' .. from)
      end
      vim.api.nvim_buf_set_text(bufnr, row - 1, startCol + 1, row - 1, endCol - 1, { tostring(from) })
      shift = #tostring(from) - #tostring(to)
    end
    if shift ~= 0 then
      ref_locations[index][3] = ref_locations[index][3] + shift
      for j = index, #ref_locations, 1 do
        local next_location = ref_locations[j + 1]
        if next_location == nil or next_location[1] ~= row then
          break
        end
        ref_locations[j + 1][2] = ref_locations[j + 1][2] + shift
        ref_locations[j + 1][3] = ref_locations[j + 1][3] + shift
        if Opts and Opts.debug_print then
          print('shifted(' .. shift .. '): ' .. ref_locations[j + 1][1] .. ', ' .. ref_locations[j + 1][2] .. ':' .. ref_locations[j + 1][3])
        end
      end
    end

    ::continue::
  end
end

--- rename the footnote content list
---@param bufnr number buffer number
---@param content_locations table locations of all footnote content
---@param from number the label to change
---@param to number the label to change to
local function content_rename(bufnr, content_locations, from, to)
  if from == to then
    return
  end
  local buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, row in ipairs(content_locations) do
    local num = string.match(buffer[row], '%d+')
    if tonumber(num) == from then
      local i, j = string.find(buffer[row], '%d+')
      vim.api.nvim_buf_set_text(bufnr, row - 1, i - 1, row - 1, j, { tostring(to) })
    elseif tonumber(num) == to then
      local i, j = string.find(buffer[row], '%d+')
      vim.api.nvim_buf_set_text(bufnr, row - 1, i - 1, row - 1, j, { tostring(from) })
    end
  end
end

--- Cleanup orphan footnote references in a given buffer
---@param bufnr number buffer number
---@param ref_locations table locations of all the footnote references
---@param content_locations table locations of all the footnote content
---@param is_deleted table flags of whether a given footnote reference is deleted
---@param from number the refernce label to be checked
local function cleanup_orphan(bufnr, ref_locations, content_locations, is_deleted, from)
  local buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local isOrphan = true
  for _, row in ipairs(content_locations) do
    local num = tonumber(string.match(buffer[row], '%d+'))
    if num == from then
      isOrphan = false
      break
    end
  end

  if isOrphan then
    for index = 1, #ref_locations, 1 do
      local location = ref_locations[index]
      if location == nil then
        goto continue
      end
      local label = string.sub(buffer[location[1]], location[2], location[3])
      local number = tonumber(string.sub(label, 3, -2))
      local row = location[1]
      local startCol = location[2]
      local endCol = location[3]

      if number == from then
        vim.api.nvim_buf_set_text(bufnr, row - 1, startCol - 1, row - 1, endCol, {})
        buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        is_deleted[index] = true
        if Opts and Opts.debug_print then
          print('cleanup_orphan: ' .. from .. ' at row ' .. row)
        end
        local shift = endCol - startCol + 1

        for j = index, #ref_locations, 1 do
          local next_location = ref_locations[j + 1]
          if next_location == nil or next_location[1] ~= row then
            break
          end
          ref_locations[j + 1][2] = ref_locations[j + 1][2] - shift
          ref_locations[j + 1][3] = ref_locations[j + 1][3] - shift
          if Opts and Opts.debug_print then
            print('shifted(' .. shift .. '): ' .. ref_locations[j + 1][1] .. ', ' .. ref_locations[j + 1][2] .. ':' .. ref_locations[j + 1][3])
          end
        end
      end
      ::continue::
    end

    return true
  else
    return false
  end
end

--- Organize footnote references and content based on occurrence
function M.organize_footnotes()
  local buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- find all footnote references with their locations
  local ref_locations = {}
  local content_locations = {}
  local is_deleted = {}
  for i, line in ipairs(buffer) do
    if string.find(line, '^%[%^%d+%]:') then
      content_locations[#content_locations + 1] = i
      goto continue
    end
    local refStart = 0
    local refEnd = nil
    while true do
      refStart, refEnd = string.find(line, '%[%^%d+%]', refStart + 1)
      if refStart == nil or refEnd == nil then
        break
      end
      ref_locations[#ref_locations + 1] = { i, refStart, refEnd }
      is_deleted[#is_deleted + 1] = false
    end
    ::continue::
  end

  -- if no footnote is found, do nothing
  if #ref_locations <= 0 then
    return
  end

  -- iterate footnotes and sort labels
  local counter = 1
  for index = 1, #ref_locations, 1 do
    local location = ref_locations[index]
    if is_deleted[index] then
      goto continue
    end
    buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local label = string.sub(buffer[location[1]], location[2], location[3])
    local number = tonumber(string.sub(label, 3, -2))

    if number and number >= counter then
      if not cleanup_orphan(0, ref_locations, content_locations, is_deleted, number) then
        if Opts and Opts.debug_print then
          print(number .. ' -> ' .. counter)
        end
        ref_rename(0, ref_locations, number, counter)
        content_rename(0, content_locations, number, counter)
        counter = counter + 1
      end
    end
    ::continue::
  end

  -- move cursor after sorting/modifying footnote content
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  -- sort footnote content
  for i = 1, #content_locations, 1 do
    buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local target = content_locations[i]
    for j = i, #content_locations, 1 do
      local current = content_locations[j]
      local num = string.match(buffer[current], '%d+')
      if tonumber(num) == i and j ~= i then
        local temp = buffer[target]
        vim.api.nvim_buf_set_text(0, target - 1, 0, target - 1, -1, { buffer[current] })
        vim.api.nvim_buf_set_text(0, current - 1, 0, current - 1, -1, { temp })
        if cursor_row == current then
          cursor_row = target
        elseif cursor_row == target then
          cursor_row = current
        end
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(0, { cursor_row, cursor_col })
end

--- get the location of next footnote ref
---@param bufnr number the buffer number (0 for current buffer)
---@param row number the row of current cursor
---@param col number the col of current cursor
---@return table | nil refLocation  location of the next footnote in a table {row, col}. If not found, return 'nil'
local function find_next(bufnr, row, col)
  local buffer = vim.api.nvim_buf_get_lines(bufnr, row - 1, -1, false)
  if #buffer > 0 then
    buffer[1] = string.sub(buffer[1], col + 1, -1)
  end
  for i, line in ipairs(buffer) do
    if string.find(line, '^%[%^%d+%]:') then
      return nil
    end
    while true do
      local refCol = string.find(line, '%[%^%d+]')
      if refCol == nil then
        break
      end
      if i == 1 then
        refCol = refCol + col
      end
      return { row - 1 + i, refCol + 1 }
    end
  end
  return nil
end

--- Go to next footnote reference
function M.next_footnote()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]

  local refLocation = find_next(0, row, col)
  if refLocation == nil then
    return
  end

  vim.api.nvim_win_set_cursor(0, { refLocation[1], refLocation[2] })
end

--- Get the location of previous footnote ref
---@param bufnr number the buffer numer (0 for current buffer)
---@param row number the row of current cursor
---@param col number the col of current cursor
---@return table | nil refLocation  location of the previous footnote in a table {row, col}. If not found, return 'nil'
local function find_prev(bufnr, row, col)
  local buffer = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  if #buffer > 0 then
    buffer[#buffer] = string.sub(buffer[#buffer], 1, col)
  end
  for i = #buffer, 1, -1 do
    local line = buffer[i]
    if string.find(line, '^%[%^%d+%]:') then
      goto continue
    end
    local refCol = 0
    local last = nil
    while true do
      refCol = string.find(line, '%[%^%d+]', refCol + 1)
      if refCol == nil then
        break
      end
      last = refCol
    end
    if last ~= nil then
      return { i, last + 1 }
    end
    ::continue::
  end
  return nil
end

--- Go to previous footnote reference
function M.prev_footnote()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]

  local refLocation = find_prev(0, row, col)
  if refLocation == nil then
    return
  end

  vim.api.nvim_win_set_cursor(0, { refLocation[1], refLocation[2] })
end

--- Startup function to setup this plugin
---@param opts table a list of custom options
function M.setup(opts)
  opts = opts or {}
  local default = {
    debug_print = false,
    keys = {
      new_footnote = '<C-f>',
      organize_footnotes = '<leader>of',
      next_footnote = ']f',
      prev_footnote = '[f',
    },
    organize_on_save = false,
    organize_on_new = false,
  }

  Opts = vim.tbl_deep_extend('force', default, opts)

  vim.api.nvim_create_autocmd('FileType', {
    desc = 'footnote.nvim keymaps',
    pattern = { 'markdown' },
    callback = function()
      if Opts.keys.new_footnote ~= '' then
        vim.keymap.set(
          { 'i', 'n' },
          Opts.keys.new_footnote,
          "<cmd>lua require('footnote').new_footnote()<cr>",
          { desc = 'Create markdown footnote', buffer = 0 }
        )
      end
      if Opts.keys.organize_footnotes ~= '' then
        vim.keymap.set('n', Opts.keys.organize_footnotes, "<cmd>lua require('footnote').organize_footnotes()<cr>", { desc = 'Organize footnote', buffer = 0 })
      end
      if Opts.keys.next_footnote ~= '' then
        vim.keymap.set('n', Opts.keys.next_footnote, "<cmd>lua require('footnote').next_footnote()<cr>", { desc = 'Next footnote', buffer = 0 })
      end
      if Opts.keys.prev_footnote ~= '' then
        vim.keymap.set('n', Opts.keys.prev_footnote, "<cmd>lua require('footnote').prev_footnote()<cr>", { desc = 'Previous footnote', buffer = 0 })
      end
    end,
  })

  if Opts.organize_on_save then
    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      group = vim.api.nvim_create_augroup('organize footnotes', { clear = true }),
      pattern = { '*.md' },
      callback = function()
        require('footnote').organize_footnotes()
      end,
    })
  end
end

return M
