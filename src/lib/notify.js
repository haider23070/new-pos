export function notify(message,type){
  const text=String(message??'');
  const inferred=type||(/success|saved|sent|created|updated|placed|completed|assigned/i.test(text)?'success':'error');
  window.dispatchEvent(new CustomEvent('nexa:notify',{detail:{text,type:inferred}}));
}
export const success=(message)=>notify(message,'success');
export const error=(message)=>notify(message,'error');
