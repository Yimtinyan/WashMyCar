import React from 'react';
import {createRoot} from 'react-dom/client';
import RefinedApp from './RefinedApp.jsx';

// Independent design explorations keep their original feature views.
export {Planner,Inventory,Watch} from './LegacyViews.jsx';
if(document.getElementById('root'))createRoot(document.getElementById('root')).render(<RefinedApp/>);
