import { initializeApp, type FirebaseApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut as fbSignOut, onAuthStateChanged, type Auth, type User } from 'firebase/auth';

declare global {
  interface Window {
    __NOONGIL_FIREBASE_CONFIG__?: Record<string, string>;
  }
}

let app: FirebaseApp | null = null;
let auth: Auth | null = null;

function getFirebaseConfig(): Record<string, string> | null {
  // In production, the backend injects config via script tag
  if (window.__NOONGIL_FIREBASE_CONFIG__) return window.__NOONGIL_FIREBASE_CONFIG__;

  // In dev mode, fall back to Vite env vars from .env.local
  const apiKey = import.meta.env.VITE_FIREBASE_API_KEY;
  if (!apiKey) return null;
  return {
    apiKey,
    authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? '',
    projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? '',
    storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ?? '',
    messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? '',
    appId: import.meta.env.VITE_FIREBASE_APP_ID ?? '',
    measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID ?? '',
  };
}

export function initFirebaseApp(): Auth | null {
  if (auth) return auth;
  const config = getFirebaseConfig();
  if (!config) return null;
  app = initializeApp(config);
  auth = getAuth(app);
  return auth;
}

export function getFirebaseAuth(): Auth | null {
  return auth;
}

export async function signInWithGoogle(): Promise<User | null> {
  const a = initFirebaseApp();
  if (!a) return null;
  const provider = new GoogleAuthProvider();
  const result = await signInWithPopup(a, provider);
  return result.user;
}

export async function signOut(): Promise<void> {
  const a = getFirebaseAuth();
  if (a) await fbSignOut(a);
}

export function onAuthChange(callback: (user: User | null) => void): () => void {
  const a = initFirebaseApp();
  if (!a) {
    callback(null);
    return () => {};
  }
  return onAuthStateChanged(a, callback);
}

export async function getIdToken(): Promise<string | null> {
  const a = getFirebaseAuth();
  if (!a?.currentUser) return null;
  return a.currentUser.getIdToken();
}
