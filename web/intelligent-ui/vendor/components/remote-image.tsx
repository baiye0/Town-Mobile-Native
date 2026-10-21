// Mobile adapter: native preview owns zoom, saving and sharing.
export function RemoteImage({src,name,onError}: {src:string;name:string;onError?():void}) {
  return <button type="button" className="remote-image-thumbnail" aria-label={`预览 ${name}`} onClick={() => (window as any).webkit?.messageHandlers.townUI.postMessage({type:'image',src,title:name})}>
    <img src={src} alt={name} loading="lazy" referrerPolicy="no-referrer" onError={onError}/>
  </button>;
}
