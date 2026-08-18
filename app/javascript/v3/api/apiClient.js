import axios from 'axios';

const { apiHost = '' } = window.tuntasConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
