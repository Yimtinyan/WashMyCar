import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {Workbook,SpreadsheetFile,FileBlob} from '@oai/artifact-tool';
const dir=fileURLToPath(new URL('.',import.meta.url));
const input=dir+'洗车药剂用途分类.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const sh=wb.worksheets.getItemAt(0);
if(process.argv[2]!=='edit'){
 console.log((await wb.inspect({kind:'workbook,sheet,table',maxChars:2500,tableMaxRows:2,tableMaxCols:6})).ndjson);
 const before=await wb.render({sheetName:sh.name,range:'A17:F21',scale:1,format:'png'});
 await fs.writeFile(dir+'before-update.png',new Uint8Array(await before.arrayBuffer()));
}else{
 const added=[
 ['玻璃保护','火球 Glass Shield','Glass Shield','未查到可靠值','挡风玻璃及车窗外侧疏水镀膜；雨天排水、减轻污物附着','先去污、去油膜并脱脂干燥；均匀薄涂、擦净余剂后固化，时间以版本说明为准'],
 ['车身养护','XIDEA 香蕉手喷 QD','香蕉 QD（快速养护喷雾）','未查到可靠值','洗车后车身快速养护、提升疏水表现；品牌展示用于镀晶／车衣车辆维护','在已清洁、冷却表面少量喷涂并用干净毛巾擦匀；不替代清洗，避开玻璃及哑光面，除非明确兼容']
 ];
 if(sh.tables.items.length){sh.tables.items[0].rows.add(null,added);}
 sh.getRange('A22:F22').copyFrom(sh.getRange('A21:F21'),'all');
 sh.getRange('A23:F23').copyFrom(sh.getRange('A21:F21'),'all');
 sh.getRange('A22:F23').values=added;
 sh.getRange('A22:F23').format.wrapText=true;
 sh.getRange('A22:F23').format.rowHeight=sh.getRange('A21:F21').format.rowHeight;
 wb.recalculate();
 console.log((await wb.inspect({kind:'region',sheetId:sh.name,range:'A21:F23',maxChars:2500,tableMaxRows:3,tableMaxCols:6})).ndjson);
 const preview=await wb.render({sheetName:sh.name,range:'A17:F23',scale:1,format:'png'});
 await fs.writeFile(dir+'updated-preview.png',new Uint8Array(await preview.arrayBuffer()));
 const output=await SpreadsheetFile.exportXlsx(wb);await output.save(dir+'洗车药剂用途分类_更新版.xlsx');
}
