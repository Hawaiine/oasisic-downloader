// api.js — Backend API request helpers
import axios from 'axios';

const api = axios.create({ baseURL: '/api', timeout: 30000 });

// ── Auto-attach Bearer token if stored ───────────────────────────
const token = localStorage.getItem('oasisic_token');
if (token) {
  api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
}

// Add interceptor for future token changes
api.interceptors.request.use(config => {
  const t = localStorage.getItem('oasisic_token');
  if (t) config.headers.Authorization = `Bearer ${t}`;
  return config;
});

export function setAuthToken(token) {
  if (token) {
    localStorage.setItem('oasisic_token', token);
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  } else {
    localStorage.removeItem('oasisic_token');
    delete api.defaults.headers.common['Authorization'];
  }
}

export function getAuthToken() {
  return localStorage.getItem('oasisic_token') || '';
}

export async function getVideoInfo(url) {
  const res = await api.get('/info', { params: { url } });
  return res.data.data ?? res.data;
}

export async function createDownload(payload) {
  const res = await api.post('/download', payload);
  return res.data;
}

export async function getTaskStatus(taskId) {
  const res = await api.get(`/download/${taskId}`);
  return res.data.data ?? res.data;
}

export async function getLyrics(title, artist, source = 'auto') {
  const res = await api.get('/lyrics', { params: { title, artist, source } });
  return res.data;
}

export async function getQueueStatus() {
  const res = await api.get('/tasks');
  return res.data;
}