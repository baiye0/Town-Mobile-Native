package town.nativeapp

import androidx.compose.foundation.gestures.*
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

@Composable fun EdgeNavigation(canBack:Boolean,canForward:Boolean,onBack:()->Unit,onForward:()->Unit,content:@Composable ()->Unit) {
    val edge=with(LocalDensity.current){24.dp.toPx()}
    val threshold=with(LocalDensity.current){64.dp.toPx()}
    val back by rememberUpdatedState(onBack);val forward by rememberUpdatedState(onForward)
    Box(Modifier.fillMaxSize().pointerInput(canBack,canForward){
        awaitEachGesture {
            val down=awaitFirstDown(requireUnconsumed=false)
            val direction=when { canBack&&down.position.x<edge->1;canForward&&down.position.x>size.width-edge->-1;else->0 }
            if(direction!=0) {
                var distance=0f
                val drag=awaitHorizontalTouchSlopOrCancellation(down.id){change,over->distance+=over;change.consume()}
                if(drag!=null) {
                    val completed=horizontalDrag(drag.id){change->distance+=change.positionChange().x;change.consume()}
                    if(completed) { if(direction==1&&distance>threshold)back();if(direction==-1&&distance < -threshold)forward() }
                }
            }
        }
    }){content()}
}
