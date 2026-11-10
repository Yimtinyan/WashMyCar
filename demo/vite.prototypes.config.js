import {defineConfig} from 'vite';
export default defineConfig({base:'./',build:{rollupOptions:{input:'prototypes.html'},outDir:'prototype-build',assetsInlineLimit:10000000},server:{port:5174,strictPort:true}});
