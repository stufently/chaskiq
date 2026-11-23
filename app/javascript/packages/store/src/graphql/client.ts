import axios from 'axios';
import { isObject, isEmpty } from 'lodash';
import store from '..';
import { errorMessage, UNAUTHENTICATED } from '../actions/status_messages';
import { setErrorCode } from '../actions/error_status_code';
import { lockPage } from '../actions/upgradePages';
import { doSignout } from '@chaskiq/store/src/actions/auth';

import { refreshToken, expireAuthentication } from '../actions/auth';

// One token refresh shared by every request that hit a 401 at the same time,
// so a burst of expired requests does not spend the refresh token twice.
let pendingRefresh: Promise<boolean> | null = null;

function refreshAuth(auth): Promise<boolean> {
  // The token changed since this request was sent: another request already
  // refreshed it (replay), or its refresh failed and signed out (null: give up).
  const current = store.getState().auth.accessToken;
  if (current !== auth.accessToken) {
    return Promise.resolve(!!current);
  }
  if (!pendingRefresh) {
    pendingRefresh = new Promise<boolean>((resolve) => {
      //@ts-ignore
      store.dispatch(refreshToken(auth, resolve));
    }).then((ok) => {
      pendingRefresh = null;
      return ok;
    });
  }
  return pendingRefresh;
}

const graphql = (query, variables, callbacks, retried = false) => {
  const { auth, current_user } = store.getState();

  // On an expired session refresh the token and replay this request once,
  // instead of losing it (and whatever the user just typed) to a page reload.
  let retrying = false;
  const refreshAndRetry = () => {
    retrying = true;
    refreshAuth(auth).then((ok) => {
      if (ok) graphql(query, variables, callbacks, true);
      else if (callbacks.always) callbacks.always();
    });
  };

  const locale =
    current_user.lang || (window.I18n && window.I18n.defaultLocale) || 'en';

  const config = {
    authorization: `Bearer ${auth.accessToken}`,
    lang: locale,
  };

  axios
    .create()
    .post(
      '/graphql',
      {
        query: query,
        variables: variables,
      },
      { headers: config }
    )
    .then((r) => {
      const data = r.data.data;
      const res = r;

      const errors = r.data.errors;

      if (isObject(errors) && !isEmpty(errors)) {
        // const errors = data[Object.keys(data)[0]];
        // callbacks['error'] ? callbacks['error'](res, errors['errors']) : null
        if (errors[0].extensions) {
          if (errors[0]?.code === UNAUTHENTICATED) {
            //@ts-ignore
            store.dispatch(errorMessage(errors[0].message));
            store.dispatch(doSignout());
            //@ts-ignore
            return store.dispatch(clearCurrentUser());
          } else {
            const error_code = errors[0].extensions.code || errors[0].code;
            store.dispatch(errorMessage(errors[0].message));
            store.dispatch(setErrorCode(error_code));
            return;
          }
        }

        const status_code = errors[0].status_code;

        switch (status_code) {
          case 500:
            //@ts-ignore
            store.dispatch(errorMessage('server error ocurred'));
            break;
          case 402:
            //
            //@ts-ignore
            store.dispatch(lockPage(errors[0].message));
            // store.dispatch(errorMessage('server error ocurred'))
            break;
          case 401:
            if (!retried) return refreshAndRetry();
            //@ts-ignore
            store.dispatch(errorMessage('session expired'));
            // still 401 with a fresh token: the session is gone
            store.dispatch(expireAuthentication());
            break;
          default:
            break;
        }

        if (callbacks.error) {
          return callbacks.error(res, errors);
        }
      }

      callbacks.success ? callbacks.success(data, res) : null;
    })
    .catch((req) => {
      if (req.response?.status === 401 && !retried) return refreshAndRetry();
      callbacks.fail ? callbacks.fail(req) : null;
      // throw r
      // const res = r.response
      // console.log("error on grapqhl client", req, error)
      switch (req.response?.status) {
        case 500:
          //@ts-ignore
          store.dispatch(errorMessage('server error ocurred'));
          break;
        case 402:
          //
          //@ts-ignore
          store.dispatch(lockPage(req.response.data.error.message));
          // store.dispatch(errorMessage('server error ocurred'))
          break;
        case 401:
          //@ts-ignore
          store.dispatch(errorMessage('session expired'));
          // still 401 with a fresh token: the session is gone
          store.dispatch(expireAuthentication());
          break;
        default:
          break;
      }

      callbacks.fatal ? callbacks.fatal('error fatale') : null;
    })
    .then((r) => {
      if (retrying) return;
      callbacks.always ? callbacks.always() : null;
    });
};

export default graphql;
