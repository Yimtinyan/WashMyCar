import {defineConfig} from 'vite';
export default defineConfig({base:'./',build:{rollupOptions:{input:'dev.html'},outDir:'build',assetsInlineLimit:10000000},server:{port:5173,strictPort:true}});
