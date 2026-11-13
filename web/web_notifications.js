// Cross-platform browser notification bridge for ABM Manager
// Supports Desktop (Chrome/Edge/Firefox/Safari), Android Chrome/Edge, and iOS 16.4+ PWA.
(function () {
  var _swRegPromise = null;

  function _hasNotificationApi() {
    return typeof window !== 'undefined' && 'Notification' in window;
  }

  function _ensureServiceWorker() {
    if (_swRegPromise) return _swRegPromise;
    if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) {
      _swRegPromise = Promise.resolve(null);
      return _swRegPromise;
    }
    _swRegPromise = navigator.serviceWorker
      .register('notifications/sw.js', { scope: './notifications/' })
      .then(function (reg) {
        if (reg && reg.active) return reg;
        return new Promise(function (resolve) {
          var sw = reg.installing || reg.waiting;
          if (!sw) {
            resolve(reg);
            return;
          }
          var timer = setTimeout(function () {
            resolve(reg);
          }, 2000);
          sw.addEventListener('statechange', function () {
            if (sw.state === 'activated' || sw.state === 'redundant') {
              clearTimeout(timer);
              resolve(reg);
            }
          });
        });
      })
      .catch(function () {
        return null;
      });
    return _swRegPromise;
  }

  window.abmNotify = {
    isSupported: function () {
      return _hasNotificationApi();
    },

    getPermission: function () {
      if (!_hasNotificationApi()) return 'unsupported';
      try {
        return Notification.permission || 'default';
      } catch (_) {
        return 'unsupported';
      }
    },

    init: async function () {
      if (!_hasNotificationApi()) return false;
      await _ensureServiceWorker();
      return true;
    },

    requestPermission: async function () {
      if (!_hasNotificationApi()) return 'unsupported';
      try {
        await _ensureServiceWorker();
        if (Notification.permission === 'granted') {
          return 'granted';
        }
        var result = Notification.requestPermission();
        if (result && typeof result.then === 'function') {
          return (await result) || Notification.permission || 'default';
        }
        return await new Promise(function (resolve) {
          Notification.requestPermission(function (perm) {
            resolve(perm || 'default');
          });
        });
      } catch (_) {
        return this.getPermission();
      }
    },

    show: async function (title, body, tag) {
      if (!_hasNotificationApi() || Notification.permission !== 'granted') {
        return false;
      }
      var safeTitle = String(title || 'ABM Manager');
      var safeBody = String(body || '');
      var safeTag = String(tag || 'abm-notif');
      var iconUrl = new URL('icons/Icon-192.png', window.location.href).href;

      var options = {
        body: safeBody,
        icon: iconUrl,
        badge: iconUrl,
        tag: safeTag,
        renotify: true,
        dir: 'auto',
        data: { url: window.location.href },
      };

      // Prefer ServiceWorkerRegistration.showNotification so Android & iOS PWA work reliably.
      try {
        var reg = await _ensureServiceWorker();
        if (reg && typeof reg.showNotification === 'function') {
          await reg.showNotification(safeTitle, options);
          return true;
        }
      } catch (_) {
        // Fallback to window Notification below
      }

      try {
        var n = new Notification(safeTitle, options);
        n.onclick = function () {
          try {
            window.focus();
          } catch (_) {}
          n.close();
        };
        return true;
      } catch (_) {
        return false;
      }
    },
  };
})();
