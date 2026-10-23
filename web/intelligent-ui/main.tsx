import {createRoot} from 'react-dom/client';
import {SurfaceTimeline,answerBlocks,blockKey} from './vendor/intelligent-ui/surfaces';
import {SurfaceArtifact,SurfaceContext} from './vendor/intelligent-ui/surface-view';
import {CodeClipboard} from './vendor/components/clipboard';
import {UIStream} from './vendor/intelligent-ui/stream';
import {intelligentUIContext} from './vendor/intelligent-ui/context';
import './vendor/intelligent-ui/styles.css';
import './mobile.css';
const root=createRoot(document.getElementById('root')!);
const timeline=new SurfaceTimeline();
const post=(message:object)=>(window as any).webkit?.messageHandlers.townUI.postMessage(message);
let snapshot='';
// Only the app invokes this entry with data through callAsyncJavaScript arguments.
(window as any).renderTownUI=(payload:any)=>{
  if(typeof payload?.source!=='string'||payload.source.length>200000)return;
  (window as any).townSavedUI=payload.saved||{};
  const messages=payload.messages||[];
  const blocks=timeline.build(messages);
  const target=messages.find((m:any)=>m.id===payload.messageID);
  const block=target&&answerBlocks(target.text).find(b=>b.type==='ui'&&b.content.trim()===payload.source.trim());
  const key=block&&blockKey(target.id,block.id);
  // Each native bubble has its own WebView. Show the resolved surface here as
  // well as in the original bubble instead of a dead cross-WebView anchor.
  if(key&&blocks.has(key))blocks.set(key,{...blocks.get(key)!,owner:true});
  const entry=key&&blocks.get(key);
  const draft=(text:string)=>post({type:'draft',text,snapshot});
  root.render(<CodeClipboard.Provider value={async text=>{post({type:'copy',text})}}><SurfaceContext.Provider value={{blocks}}>
    {entry?.error&&<p role="status" className="iui-notice">界面未更新：{entry.error}，已保留可用版本。</p>}
    <SurfaceArtifact messageId={target?.id} blockId={block?.id||'ui-0'} source={payload.source} streaming={target?.streaming||false}
      storageKey={payload.storageKey} onSnapshot={text=>{try{JSON.parse(text);snapshot=text}catch{snapshot=''}}}
      onEdit={()=>draft('请根据当前界面和我的选择继续修改。')}
      onContinue={text=>draft(text)}/>
  </SurfaceContext.Provider></CodeClipboard.Provider>);
};
document.addEventListener('click',e=>{
  const button=(e.target as Element).closest('button');
  if(button?.getAttribute('aria-label')==='展开界面') { e.preventDefault();e.stopPropagation();post({type:'expand'}); }
},true);
// Pure parser exports also power the local regression suite.
export {SurfaceTimeline,UIStream,intelligentUIContext};
post({type:'ready'});
