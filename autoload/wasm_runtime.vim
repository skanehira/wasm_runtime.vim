" wasm_runtime
" Author: skanehira
" License: MIT

let s:SECTION_ID = {
      \ 'CUSTOM': 0,
      \ 'TYPE': 1,
      \ 'FUNCTION': 3,
      \ 'EXPORT': 7,
      \ 'CODE': 10
      \ }

let s:INSTRUCTIONS = {
      \ 32: 'local.get',
      \ 106: 'i32.add',
      \ 11: 'end',
      \ }

function! s:runtime_new(module) abort
  let exports = {}
  for export in a:module.export_section
    let exports[export.name] = export.idx
  endfor

  let functions = []

  for i in range(0, len(a:module.function_section)-1)
    let func_body = a:module.code_section[i]
    call add(functions, { 'body': func_body.code })
  endfor

  let runtime = {
        \ 'exports': exports,
        \ 'functions': functions,
        \ 'frame': [],
        \ 'stack': [],
        \ }

  function! runtime.resolve_func(func_name) dict abort
    let idx = self.exports[a:func_name]
    return self.functions[idx]
  endfunction

  function! runtime.new_frame(inst, args) dict abort
    let frame = {
          \ 'local_stack': a:args,
          \ 'pc': 0,
          \ 'inst': a:inst,
          \ }

    function! frame.inc() dict abort
      let self.pc += 1
    endfunction

    return frame
  endfunction

  function! runtime.invoke(func_name, args) dict abort
     let func = self.resolve_func(a:func_name)
     let frame = self.new_frame(func.body, a:args)
     call add(self.frame, frame)
     return self.execute()
  endfunction

  function! runtime.current_frame() dict abort
    return self.frame[-1] 
  endfunction

  function! runtime.pop_frame() dict abort
    let self.frame = self.frame[:-2]
  endfunction

  function! runtime.inc_pc() dict abort
    let frame = self.current_frame()
    let frame.pc += 1
  endfunction

  function! runtime.stack_pop() dict abort
    let a = self.stack[-1]
    let self.stack = self.stack[:-2]
    return a
  endfunction

  function! runtime.execute() dict abort
    while v:true
      let inst = self.instruction()
      if empty(inst)
        break
      endif

      call self.inc_pc()

      if inst.name ==# 'local.get'
        let value = self.current_frame().local_stack[inst.value]
        call add(self.stack, value)
      elseif inst.name ==# 'i32.add'
        let a = str2nr(self.stack_pop())
        let b = str2nr(self.stack_pop())
        call add(self.stack, a + b)
      elseif inst.name ==# 'end'
        " do nothing
      endif
    endwhile

    return self.stack_pop()
  endfunction

  function! runtime.instruction() dict abort
    while v:true
      if len(self.frame) == 0
        return {}
      endif
      let frame = self.current_frame()
      let insts = frame.inst
      if frame.pc < len(insts)
        return insts[frame.pc]
      endif
      " popup last frame
      call self.pop_frame()
    endwhile
  endfunction

  return runtime
endfunction

function! s:to_ascii(bytes) abort
  return join(map(a:bytes, { _, val -> nr2char(val) }),'')
endfunction

function! s:decoder_new(blob) abort
  let decoder = {
        \ 'blob': a:blob,
        \ 'pos': 0,
        \ }

  function! decoder.is_end() dict abort
    return self.pos >= len(self.blob)
  endfunction

  function! decoder.skip(count) dict abort
    let self.pos += a:count
  endfunction

  function! decoder.decode(count) dict abort
    if self.pos >= len(self.blob)
      throw 'end of file'
    endif
    let start = self.pos
    let end = start + a:count - 1
    let bytes = []
    for i in range(start, end)
      call add(bytes, self.blob[i])
    endfor
    let self.pos += a:count
    return bytes
  endfunction

  function! decoder.decode_section_header() dict abort
    let section_id = self.decode(1)[0]
    let size = self.decode(1)[0]
    return [section_id, size]
  endfunction

  return decoder
endfunction


function! s:module_load(file) abort
  let module = {
        \ 'magic': '',
        \ 'version': '',
        \ 'type_section': [],
        \ 'function_section': [],
        \ 'code_section': [],
        \ 'export_section': [],
        \ }

  function! module.decode_type_section(decoder) dict abort
    let func_types = []
    let count = a:decoder.decode(1)[0]

    for _ in range(1, count)
      let func_type = a:decoder.decode(1)[0]
      if func_type !=# 96
        throw 'invalid func_type: ' .. func_type
      endif
      let func = {
            \ 'params': [],
            \ 'results': [],
            \ }
      let num_params = a:decoder.decode(1)[0]

      for _ in range(1, num_params)
        if a:decoder.decode(1)[0] !=# 127
          throw 'function! parameter only support i32'
        endif
        call add(func.params, 'i32')
      endfor

      let num_results = a:decoder.decode(1)[0]

      for _ in range(1, num_results)
        if a:decoder.decode(1)[0] !=# 127
          throw 'function! results only support i32'
        endif
        call add(func.results, 'i32')
      endfor

      call add(func_types, func)
    endfor

    return func_types
  endfunction

  function! module.decode_function_section(decoder) dict abort
    let func_section = []
    let count = a:decoder.decode(1)[0]
    for _ in range(1, count)
      let idx = a:decoder.decode(1)[0]
      call add(func_section, idx)
    endfor
    return func_section
  endfunction

  function! module.decode_export_section(decoder) dict abort
    let count = a:decoder.decode(1)[0]
    let exports = []
    for _ in range(1, count)
      let str_len = a:decoder.decode(1)[0]
      let name = s:to_ascii(a:decoder.decode(str_len))
      let kind = a:decoder.decode(1)[0]

      if kind !=# 0
        throw 'only support function!: ' .. kind
      endif

      let idx = a:decoder.decode(1)[0]

      " NOTE: only support function!
      call add(exports, {
            \ 'name': name,
            \ 'idx': idx,
            \ })
    endfor
    return exports
  endfunction

  function! module.decode_function_body(bytes) dict abort
    let decoder = s:decoder_new(a:bytes)

    " skip function! locals
    let skip_count = decoder.decode(1)[0]
    call decoder.skip(skip_count)

    let function_body = {
          \ 'code': []
          \ }

    while !decoder.is_end()
      let op = decoder.decode(1)[0]
      let inst_name = s:INSTRUCTIONS[op]
      let inst = {'name': inst_name}
      if inst_name ==# 'local.get'
        let local_idx = decoder.decode(1)[0]
        let inst['value'] = local_idx
      endif
      call add(function_body.code, inst)
    endwhile

    return function_body
  endfunction

  function! module.decode_code_section(decoder) dict abort
    let functions = []
    let count = a:decoder.decode(1)[0]
    for _ in range(1, count)
      let body_size = a:decoder.decode(1)[0]
      let body = a:decoder.decode(body_size)
      call add(functions, self.decode_function_body(body))
    endfor
    return functions
  endfunction

  function! module.decode(section, decoder) dict abort
    if a:section ==# s:SECTION_ID.TYPE
      return self.decode_type_section(a:decoder)
    elseif a:section ==# s:SECTION_ID.FUNCTION
      return self.decode_function_section(a:decoder)
    elseif a:section ==# s:SECTION_ID.CODE
      return self.decode_code_section(a:decoder)
    elseif a:section ==# s:SECTION_ID.EXPORT
      return self.decode_export_section(a:decoder)
    else
      throw 'unsupported section'
    endif
  endfunction

  function! module.add_section(id, section) dict abort
    if a:id ==# s:SECTION_ID.TYPE
      let self.type_section = a:section
    elseif a:id ==# s:SECTION_ID.FUNCTION
      let self.function_section = a:section
    elseif a:id ==# s:SECTION_ID.CODE
      let self.code_section = a:section
    elseif a:id ==# s:SECTION_ID.EXPORT
      let self.export_section = a:section
    else
      throw 'unsupported section'
    endif
  endfunction

  function! module.load(file) dict abort
    let blob = readfile(a:file, 'B')
    let decoder = s:decoder_new(blob)

    let magic = s:to_ascii(decoder.decode(4))
    if magic !=# 'asm'
      throw a:file .. ' is not wasm binary: ' .. magic
    endif

    let ver = decoder.decode(4)[0]

    if ver !=# 1
      throw 'only support version 1'
    endif

    let self.magic = magic
    let self.version = ver

    while !decoder.is_end()
      let [section_id, size] = decoder.decode_section_header()
      if section_id == s:SECTION_ID.CUSTOM
        continue
      endif
      let section_decoder = s:decoder_new(decoder.decode(size))
      let section = self.decode(section_id, section_decoder)
      call self.add_section(section_id, section)
    endwhile

    return self
  endfunction

  return module.load(a:file)
endfunction

function! wasm_runtime#run(...) abort
  try
    let file = a:1
    let func_name = a:2
    let args = a:000[2:]
    let module = s:module_load(file)
    let runtime = s:runtime_new(module)
    echom runtime.invoke(func_name, args)
  catch /.*/
    echohl ErrorMsg
    echom v:exception
    echohl None
  endtry
endfunction
