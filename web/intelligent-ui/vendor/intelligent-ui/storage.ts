// Mobile host adapter. Persist by endpoint/scene scope; generated Workers never
// receive the bridge or stored values belonging to another surface.
import type {Value} from './runtime';
type Values=Record<string,Value>;
const memory=new Map<string,Values>();
export async function loadUIState(key:string):Promise<Values|undefined>{
  return memory.get(key) || (window as any).townSavedUI?.[key];
}
export function rememberUIState(key:string,values:Values){
  memory.set(key,{...values});
  if(memory.size>200)memory.delete(memory.keys().next().value!);
  (window as any).webkit?.messageHandlers.townUI.postMessage({type:'save',key,values});
}
export async function saveUIState(key:string,values:Values){rememberUIState(key,values)}
