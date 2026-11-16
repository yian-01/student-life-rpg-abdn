(() => {
  const lockName = 'student-life-rpg-storage';
  let database;
  const storeName = 'entries';

  function openDatabase() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(lockName, 1);
      request.onupgradeneeded = () => request.result.createObjectStore(storeName);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  window.studentLifeStart = () => new Promise((resolve, reject) => {
    if (!navigator.locks || !window.indexedDB) {
      resolve('unavailable');
      return;
    }
    navigator.locks.request(lockName, {ifAvailable: true}, async lock => {
      if (!lock) {
        resolve('already-open');
        return;
      }
      database = await openDatabase();
      resolve('ready');
      await new Promise(release => {
        window.addEventListener('pagehide', release, {once: true});
      });
      database.close();
    }).catch(reject);
  });

  // An old tab restored from the back/forward cache must reacquire the lease.
  window.addEventListener('pageshow', event => {
    if (event.persisted) location.reload();
  });

  function rangeFor(path) {
    const prefix = `${path}/`;
    return IDBKeyRange.bound(prefix, `${path}0`, false, true);
  }

  window.studentLifeFile = (operation, path, destination, bytes) =>
    new Promise((resolve, reject) => {
      const readOnly = ['type', 'read', 'list'].includes(operation);
      const transaction = database.transaction(storeName, readOnly ? 'readonly' : 'readwrite');
      const entries = transaction.objectStore(storeName);
      let result = null;
      let error;
      const abort = message => {
        error = new Error(message);
        transaction.abort();
      };
      transaction.oncomplete = () => resolve(result);
      transaction.onabort = () => reject(error || transaction.error || new Error('Storage transaction failed'));
      const get = (name, use) => {
        const request = entries.get(name);
        request.onsuccess = () => use(request.result);
      };
      const directoryEntries = (name, use) => {
        const request = entries.getAllKeys(rangeFor(name));
        request.onsuccess = () => use(request.result);
      };
      if (operation === 'mkdir') {
        get(path, entry => {
          if (entry === undefined) entries.add({type: 'directory'}, path);
          else if (entry.type !== 'directory') abort('A file occupies the directory');
        });
      } else if (operation === 'write') {
        entries.put({type: 'file', bytes}, path);
      } else if (operation === 'list') {
        directoryEntries(path, keys => {
          result = [...new Set(keys.map(key => key.slice(path.length + 1).split('/')[0]))];
        });
      } else {
        get(path, entry => {
          if (operation === 'type') {
            result = entry?.type || 'missing';
          } else if (!entry) {
            abort('The entry does not exist');
          } else if (operation === 'read') {
            if (entry.type !== 'file') abort('The entry is not a file');
            else result = entry.bytes;
          } else if (operation === 'copy' || operation === 'rename') {
            if (entry.type === 'directory') {
              directoryEntries(path, keys => {
                entries.put(entry, destination);
                entries.delete(path);
                for (const key of keys) {
                  get(key, child => {
                    entries.put(child, destination + key.slice(path.length));
                    entries.delete(key);
                  });
                }
              });
            } else {
              entries.put(entry, destination);
              if (operation === 'rename') entries.delete(path);
            }
          } else if (operation === 'delete') {
            if (entry.type === 'directory') entries.delete(rangeFor(path));
            entries.delete(path);
          } else {
            abort('Unknown storage operation');
          }
        });
      }
    });

  window.studentLifeRequest = async (method, path, headersJson, body, limit) => {
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 45000);
    try {
      const response = await fetch(path, {
        method,
        headers: JSON.parse(headersJson),
        body,
        credentials: 'omit',
        redirect: 'error',
        cache: 'no-store',
        signal: abort.signal,
      });
      const result = {status: response.status, etag: response.headers.get('ETag'), tooLarge: false};
      const cap = response.ok || response.status === 304 ? limit : 4096;
      const chunks = [];
      let size = 0;
      if (response.body && cap > 0) {
        const reader = response.body.getReader();
        for (;;) {
          const {done, value} = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > cap) {
            await reader.cancel();
            result.tooLarge = true;
            size = 0;
            chunks.length = 0;
            break;
          }
          chunks.push(value);
        }
      } else {
        await response.body?.cancel();
      }
      result.bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        result.bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      return result;
    } finally {
      clearTimeout(timeout);
    }
  };
})();
