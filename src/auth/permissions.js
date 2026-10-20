export const ROLES = ['Developer','Admin','Manager','Cashier','Call Center','Dispatcher','Delivery Boy','Order Taker','Kitchen Staff']

// Frontend permissions are UX guards only. Sensitive actions are also enforced by SQL/RPC.
export const ROLE_PERMISSIONS = {
  Developer: ['*'],
  Admin: ['*'],
  Manager: ['menu.manage','dashboard.view','pos.*','kitchen.*','inventory.*','staff.*','accounting.*','reports.*','purchasing.*','shift.*','settings.*','operations.*','orders.cancel','orders.assign_rider'],
  Cashier: ['dashboard.view','pos.view','pos.create','pos.edit','pos.pay','pos.print','customers.view'],
  'Call Center': ['dashboard.view','pos.view','pos.create','pos.edit','pos.print','customers.view','delivery.view'],
  Dispatcher: ['dashboard.view','pos.view','pos.create','pos.edit','pos.print','customers.view','delivery.view','orders.assign_rider','operations.dispatcher'],
  'Delivery Boy': ['delivery.my_orders','delivery.update','attendance.self','settings.self'],
  'Order Taker': ['waiter.app','pos.create','pos.edit','pos.print','customers.view'],
  'Kitchen Staff': ['kitchen.kds'],
}

export const ROLE_ALIASES = {
  developer:'Developer', admin:'Admin', manager:'Manager', cashier:'Cashier',
  'call center':'Call Center', callcenter:'Call Center',
  dispatcher:'Dispatcher', despature:'Dispatcher', despatcher:'Dispatcher',
  rider:'Delivery Boy', 'delivery boy':'Delivery Boy', delivery:'Delivery Boy',
  'kitchen staff':'Kitchen Staff', kitchen:'Kitchen Staff',
  waiter:'Order Taker', 'order taker':'Order Taker', ordertaker:'Order Taker',
}
export function normalizeRole(role='Cashier') { return ROLE_ALIASES[String(role).trim().toLowerCase()] || role }
const matches=(grant,wanted)=>grant==='*'||grant===wanted||(grant.endsWith('.*')&&wanted.startsWith(grant.slice(0,-1)))
export function can(role,permission,overrides=[]){
  const normalized=normalizeRole(role)
  const grants=[...(ROLE_PERMISSIONS[normalized]||[]),...overrides.filter(x=>x.allowed).map(x=>x.permission_key)]
  if(overrides.some(x=>x.permission_key===permission&&x.allowed===false))return false
  return grants.some(g=>matches(g,permission))
}
