import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
const require=createRequire(new URL('../../demo/package.json',import.meta.url));
const React=require('react'),{renderToStaticMarkup}=require('react-dom/server'),icons=require('lucide-react');
const names=['ChevronLeft','ChevronRight','Plus','SlidersHorizontal','Search','Car','FlaskConical','Watch','Check','ArrowUpDown','ChevronDown','ArrowRight','MoreHorizontal','CheckCircle2','Pause','Play','Package','WifiOff','Wifi','Signal','BatteryFull'];
const svg=Object.fromEntries(names.map(name=>[name,renderToStaticMarkup(React.createElement(icons[name],{size:24,strokeWidth:1.7,color:'#1D3137'}))]));
await fs.writeFile(new URL('icons.json',import.meta.url),JSON.stringify(svg,null,2));
