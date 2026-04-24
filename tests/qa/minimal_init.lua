-- Pure-headless init: only adds the plugin's lua/ to runtimepath; no rtp pollution.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
