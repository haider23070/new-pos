import React from 'react'
import {createRoot}from'react-dom/client'
import {AuthProvider}from'./context/AuthContext'
import App from'./app/App'
import AlertCenter from'./components/AlertCenter'
import'./style.css'
createRoot(document.getElementById('root')).render(<AuthProvider><App/><AlertCenter/></AuthProvider>)
