const {contextBridge,ipcRenderer}=require('electron');
const channels=['load','cards','catalogue','decks','aggregate','card-filter','owned','toggle','save-build','import-ydk','export-ydk','backup','restore','hyper','combo','save-buckets','products','skus','printing','prices'];
contextBridge.exposeInMainWorld('deckLab',Object.fromEntries(channels.map(name=>[name,(...args)=>ipcRenderer.invoke(name,...args)])));
