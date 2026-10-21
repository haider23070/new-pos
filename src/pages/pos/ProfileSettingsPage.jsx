import React, { useEffect, useRef, useState } from 'react'
import { ImagePlus, Save } from 'lucide-react'
import './ProfileSettingsPage.css'

export default function ProfileSettingsPage({
  profile = {},
  printers = [],
  onSave
}) {
  const fileRef = useRef(null)
  const [saving, setSaving] = useState(false)
  const [preview, setPreview] = useState(profile.avatar_url || '')
  const [form, setForm] = useState({
    first_name: profile.first_name || profile.name?.split(' ')?.[0] || '',
    last_name: profile.last_name || profile.name?.split(' ')?.slice(1).join(' ') || '',
    email: profile.email || '',
    username: profile.username || profile.email?.split('@')?.[0] || '',
    current_password: '',
    new_password: '',
    logout_all_devices: false,
    image: null,
    default_order_type: profile.default_order_type || 'Delivery',
    default_redirect_page: profile.default_redirect_page || 'delivery_screen',
    receipt_printer_name: profile.receipt_printer_name || '',
    default_page_pos: profile.default_page_pos || 'new_order'
  })

  useEffect(() => {
    setForm(x => ({
      ...x,
      first_name: profile.first_name || profile.name?.split(' ')?.[0] || '',
      last_name: profile.last_name || profile.name?.split(' ')?.slice(1).join(' ') || '',
      email: profile.email || '',
      username: profile.username || profile.email?.split('@')?.[0] || '',
      default_order_type: profile.default_order_type || x.default_order_type,
      default_redirect_page: profile.default_redirect_page || x.default_redirect_page,
      receipt_printer_name: profile.receipt_printer_name || '',
      default_page_pos: profile.default_page_pos || x.default_page_pos
    }))
    setPreview(profile.avatar_url || '')
  }, [profile])

  const set = (key, value) => setForm(x => ({ ...x, [key]: value }))

  const pickImage = e => {
    const file = e.target.files?.[0]
    if (!file) return
    set('image', file)
    const reader = new FileReader()
    reader.onload = () => setPreview(String(reader.result || ''))
    reader.readAsDataURL(file)
  }

  const submit = async e => {
    e.preventDefault()
    if (!onSave || saving) return
    setSaving(true)
    try {
      await onSave(form)
      setForm(x => ({ ...x, current_password: '', new_password: '' }))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="mprofile-page">
      <div className="mprofile-card">
        <div className="mprofile-heading">
          <h4>Profile Setting</h4>
        </div>

        <form className="mprofile-form" onSubmit={submit}>
          <ProfileRow label="First Name *">
            <input value={form.first_name} readOnly placeholder="First Name"/>
          </ProfileRow>

          <ProfileRow label="Last Name *">
            <input value={form.last_name} readOnly placeholder="Last Name"/>
          </ProfileRow>

          <ProfileRow label="Email Address *">
            <input value={form.email} readOnly placeholder="Email Address"/>
          </ProfileRow>

          <ProfileRow label="Username *">
            <input value={form.username} readOnly placeholder="Username"/>
          </ProfileRow>

          <ProfileRow label="Current Password *">
            <input
              value={form.current_password}
              onChange={e=>set('current_password', e.target.value)}
              type="password"
              autoComplete="current-password"
              placeholder="Password"
            />
          </ProfileRow>

          <ProfileRow label="New Password *">
            <input
              value={form.new_password}
              onChange={e=>set('new_password', e.target.value)}
              type="password"
              autoComplete="new-password"
              placeholder="Password"
            />
          </ProfileRow>

          <ProfileRow label="Logout from all devices">
            <label className="mprofile-check">
              <input
                type="checkbox"
                checked={form.logout_all_devices}
                onChange={e=>set('logout_all_devices', e.target.checked)}
              />
              <span>When changing password, logout from all other devices</span>
            </label>
          </ProfileRow>

          <ProfileRow label="Preview">
            <div className="mprofile-preview">
              {preview
                ? <img src={preview} alt="Profile preview"/>
                : <div className="mprofile-avatar">{(form.first_name || 'U').slice(0,1).toUpperCase()}</div>}
            </div>
          </ProfileRow>

          <ProfileRow label="Image">
            <div className="mprofile-upload" onClick={()=>fileRef.current?.click()}>
              <ImagePlus size={26}/>
              <strong>{form.image ? form.image.name : 'Drag and drop a file here or click'}</strong>
              <span>Choose file</span>
              <input ref={fileRef} type="file" accept="image/*" onChange={pickImage} hidden/>
            </div>
          </ProfileRow>

          <ProfileRow label="Default Order Type">
            <select value={form.default_order_type} onChange={e=>set('default_order_type', e.target.value)}>
              <option>Dine-In</option>
              <option>Take-Away</option>
              <option>Delivery</option>
              <option>ThirdParty</option>
              <option>Car Service</option>
            </select>
          </ProfileRow>

          <ProfileRow label="Default Redirect Page">
            <select value={form.default_redirect_page} onChange={e=>set('default_redirect_page', e.target.value)}>
              <option value="home">Home</option>
              <option value="pos">POS</option>
              <option value="delivery_screen">Delivery Screen</option>
            </select>
          </ProfileRow>

          <ProfileRow label="Receipt Printer">
            <select value={form.receipt_printer_name} onChange={e=>set('receipt_printer_name', e.target.value)}>
              <option value="">Select Receipt Printer</option>
              {printers.map(p => {
                const value = p.name || p.printer_name || p.id
                return <option key={p.id || value} value={value}>{p.name || p.printer_name || value}</option>
              })}
            </select>
          </ProfileRow>

          <ProfileRow label="Default Page for POS">
            <select value={form.default_page_pos} onChange={e=>set('default_page_pos', e.target.value)}>
              <option value="processing_order">All Processing Order</option>
              <option value="dine_in">Dine-In</option>
              <option value="take_away">Take-Away</option>
              <option value="delivery">Delivery</option>
              <option value="third_party">Third-Party</option>
              <option value="new_order">New Order</option>
            </select>
          </ProfileRow>

          <div className="mprofile-save-row">
            <button type="submit" disabled={!onSave || saving} className="mprofile-save">
              <Save size={15}/>
              {saving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ProfileRow({ label, children }) {
  return (
    <div className="mprofile-row">
      <label>{label}</label>
      <div>{children}</div>
    </div>
  )
}
