" mbed.vim - Execute mbed CLI commands from within Vim
" Author:    marrakchino (nabilelqatib@gmail.com)
" License:   MIT (https://opensource.org/licenses/MIT)
" Version:   1.0
"
" This file contains routines that may be used to execute mbed CLI commands
" from within VIM. It depends on mbed OS. Therefore, 
" you must have mbed CLI correctly installed 
" (see https://github.com/ARMmbed/mbed-cli#installation).
"
" In command mode:
" <leader>c:  Compile the current application
" <leader>C:  Clean the build directory and compile the current application
" <leader>cf: Compile and flash the built firmware onto a connected target
" <leader>cv: Compile the current application in verbose mode
" <leader>cV: Compile the current application in very verbose mode
" <leader>n:  Create a new mbed program or library
" <leader>s:  Synchronize all library and dependency references
" <leader>t:  Find, build and run tests
" <leader>d:  Import missing dependencies
" <leader>a:  Prompt for an mbed library to add
" <leader>r:  Prompt for an mbed library to remove
" <leader>l:  Display the dependency tree
" <F9>:       Close the error buffer (when open)
" <F12>:      Set the current application's target and toolchain 
"
" Add <library_name> --       Add the specified library. When no argument is given,
"                             you are prompted for the name of the library
" Remove <library_name> --    Remove the specified library. When no argument is given,
"                             you are prompted for the name of the library
" SetToolchain <toolchain> -- Set a toolchain (ARM, GCC_ARM, IAR)
" SetTarget <target> --       Set a target
"
" Additionally, you can specify the values of these variables in your vim
" configuration file, to suit this plugin to your needs (in case you always
" use the same mbed target/toolchain):
"   w:mbed_target --      The name of your target. mbed CLI doesn't check that your
"                         target name is correct, so make sure you don't misspell it.
"   w:mbed_toolchain --   The name of the used toolchain (ARM, GCC_ARM, IAR).
"
" Notes:
"   When you execute an unsuccessful "compile" command an "error buffer" is open 
"   at the left of the current Vim window (otherwise a message is echoed when 
"   the compilation was successful). This buffer is a scratch and can't be
"   saved. You can re-compile your program with this buffer still open, it 
"   will refresh with the new output reloaded, and no additional buffer
"   is opened. You can close this buffer with <F9>. 
"

function! ReadTargetandToolchainFromConfigFile(file)
  if filereadable(a:file)
    if match(readfile(a:file), "TARGET") != -1
      let w:mbed_target = substitute(system("grep 'TARGET' " . a:file . " | cut -f2 -d="), '\n', '', 'g')
    endif
    if match(readfile(a:file), "TOOLCHAIN") != -1
      let w:mbed_toolchain = substitute(system("grep 'TOOLCHAIN' " . a:file . " | cut -f2 -d="), '\n', '', 'g')
    endif
  endif
endfunction

if !exists("w:mbed_target")
  let w:mbed_target = ""
endif

if !exists("w:mbed_toolchain")
  let w:mbed_toolchain = ""
endif

" read from ~/.mbed if found
call ReadTargetandToolchainFromConfigFile(expand("~/.mbed"))
" eventually override the global configuration with the local .mbed file content
call ReadTargetandToolchainFromConfigFile(".mbed")

function! MbedGetTargetandToolchain( force )
  if !executable('mbed')
    echoerr "Couldn't find mbed CLI tools."
    finish
  endif
  if w:mbed_target == "" || a:force != 0
    let l:target_list = system("mbed target -S")
    " if has("win32") " TODO (one day)
    let l:target = system('mbed target')
    if v:shell_error || match(l:target, "No") != -1
      echo "There was a problem checking the current target."
      let l:target = input("Please enter your mbed target name: ") 
      " see if we can find the target name in the list of supported targets
      " FIXME: pitfall, when a single letter is given for example ("A"), match
      " will assume it's OK, need to search for whole word...
      if match(l:target_list, l:target) == -1
        echo "\rThe target chosen isn't supported, please check
              \ the spelling and your current version of mbed-OS then try again."
        vnew | set buftype=nofile
        let l:target_list = "\nSupported targets:\n\n" . l:target_list
        put =l:target_list
        normal ggj
        return
      endif
    endif
    let w:mbed_target = substitute(substitute(l:target, '\[[^]]*\] ', '', 'g'), '\n', '', 'g')
  endif

  if w:mbed_toolchain == "" || a:force != 0
    " if has("win32") " TODO (one day)
    let l:toolchain = system('mbed toolchain')
    if v:shell_error || match(l:toolchain, "No") != -1
      echo "\rThere was a problem checking the current toolchain."
      let l:toolchain = input("Please choose a toolchain (ARM, GCC_ARM, IAR): ") 
      if l:toolchain != "ARM" && l:toolchain != "GCC_ARM" && l:toolchain != "IAR"
        echo "\rWrong toolchain, please try again."
        return
      endif
    endif
    let w:mbed_toolchain = substitute(substitute(l:toolchain, '\[[^]]*\] ', '', 'g'), '\n', '', 'g')
  endif
endfunction

function! MbedNew()
  execute "!mbed new ."
endfunction

function! MbedSync()
  execute "!mbed sync"
endfunction

function! MbedDeploy()
  execute "!mbed deploy"
endfunction

function! PasteContentToErrorBuffer()
  if exists("g:error_buffer_number")
    if bufexists(g:error_buffer_number)
      " buffer exists and is visible
      if bufwinnr(g:error_buffer_number) > 0
        call CleanErrorBuffer()
      else
        execute "vert belowright sb " . g:error_buffer_number
        set buftype=nofile
      endif
    else
      vnew
      let g:error_buffer_number = bufnr('%')
      set buftype=nofile
    endif
  else
    vnew
    set buftype=nofile
    let g:error_buffer_number = bufnr('%')
  endif

  call CleanErrorBuffer()
  silent put=@o
  normal ggddG
endfunction

" Clear the error buffer's content
function! CleanErrorBuffer()
  " see  https://stackoverflow.com/questions/28392784/vim-drop-for-buffer-jump-to-window-if-buffer-is-already-open-with-tab-autoco
  execute "set switchbuf+=useopen"
  execute "sbuffer " . g:error_buffer_number
  normal ggdG
endfunction

" Close compilation error buffer opened due to mbed compile call
function! CloseErrorBuffer()
  if (exists("g:error_buffer_number"))
    execute "bdelete " . g:error_buffer_number
    let g:error_buffer_number = -1
  endif
endfunction

" Compile the current program with the given flag(s) (-f, -c, -v, -vv)
function! MbedCompile(flags)
  call MbedGetTargetandToolchain(0) 
  execute 'wa'
  let @o = system("mbed compile" . " -m " . w:mbed_target . " -t " . w:mbed_toolchain . " " . a:flags)
  if !empty(@o)
    " <Image> pattern not found
    if match(getreg("o"), "Image") == -1
      call PasteContentToErrorBuffer()
    else
      echo "Compilation ended successfully."
    endif
  endif
endfunction

function! MbedAdd(...)
  if a:0 == 0
    call PromptForLibraryToAdd()
  else
    for library in a:000
      execute '!mbed add ' . library
    endfor
  endif
endfunction

function! PromptForLibraryToAdd()
  let l:library_name = input("Please enter the name/URL of the library to add: ")
  call MbedAdd(l:library_name)
endfunction

function! MbedRemove(...)
  if a:0 == 0
    call PromptForLibraryToRemove()
  else
    for library in a:000
      execute '!mbed remove ' . library
    endfor
  endif
endfunction

function! PromptForLibraryToRemove()
  let l:library_name = input("Please enter the name/URL of the library to remove: ")
  call MbedRemove(l:library_name)
endfunction

function! MbedList()
  let @o = system("mbed ls")
  if !empty(@o)
    " no output 
    new | set buftype=nofile
    silent put=@o
    " Delete empty lines
    execute "g/^$/d"
    normal 1G
    let l:newheight = line("$")
    let l:newheight += 1
    " winheight: hight of the current window
    if l:newheight < winheight(0)
      execute "resize " . l:newheight
    endif
  endif
endfunction

function! MbedTest()
  execute 'wa'
  let @t = system("mbed test")
  if !empty(@t)
    " TODO: find a pattern in the output to notify that the tests were successful
    vnew
    set buftype=nofile
    silent put=@t
    normal G
  endif
endfunction

" command-mode mappings
map <leader>c  :call MbedCompile("")<CR>
map <leader>C  :call MbedCompile("-c")<CR>
map <leader>cf :call MbedCompile("-f")<CR>
map <leader>cv :call MbedCompile("-v")<CR>
map <leader>cV :call MbedCompile("-vv")<CR>
map <leader>n  :call MbedNew()<CR>
map <leader>s  :call MbedSync()<CR>
map <leader>t  :call MbedTest()<CR>
map <leader>d  :call MbedDeploy()<CR>
map <leader>a  :call MbedAdd("")<CR>
map <leader>r  :call MbedRemove("")<CR>
map <leader>l  :call MbedList()<CR>
map <F9>       :call CloseErrorBuffer()<CR>
map <F12>      :call MbedGetTargetandToolchain(1)<CR>

" commands
command! -nargs=? Add :call MbedAdd("<args>")
command! -nargs=? Remove :call MbedRemove("<args>")
command! -nargs=1 SetToolchain :let w:mbed_toolchain="<args>"
command! -nargs=1 SetTarget :let w:mbed_target="<args>"
